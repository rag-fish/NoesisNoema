// filepath: NoesisNoema/Shared/Utils/GoogleDriveDownloader.swift
// Project: NoesisNoema
// Description: Resumable Google Drive downloader with SHA256 verification for large GGUF files
// License: MIT License

import Foundation
import CryptoKit

/// Google Drive から大規模GGUFファイルをダウンロード（再開可能 + 完全性検証）
actor GoogleDriveDownloader {

    /// ダウンロードタスク定義
    struct DownloadTask: Sendable {
        let fileId: String
        let fileName: String
        let expectedSizeBytes: UInt64?
        let sha256: String?

        init(fileId: String, fileName: String, expectedSizeBytes: UInt64? = nil, sha256: String? = nil) {
            self.fileId = fileId
            self.fileName = fileName
            self.expectedSizeBytes = expectedSizeBytes
            self.sha256 = sha256
        }
    }

    /// ダウンロード進捗状態
    struct DownloadProgress: Sendable {
        var downloadedBytes: UInt64 = 0
        var totalBytes: UInt64 = 0
        var percentage: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(downloadedBytes) / Double(totalBytes)
        }
        var statusMessage: String = ""
    }

    private var currentProgress = DownloadProgress()

    /// Google Drive から GGUF モデルをダウンロード（再開可能）
    func download(task: DownloadTask, to destinationDir: URL, progressHandler: ((DownloadProgress) -> Void)? = nil) async throws -> URL {
        let destinationURL = destinationDir.appendingPathComponent(task.fileName)
        let partialURL = destinationDir.appendingPathComponent(task.fileName + ".partial")

        // 既存ファイルがあれば検証してスキップ
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            currentProgress.statusMessage = "Verifying existing file..."
            progressHandler?(currentProgress)

            if let hash = task.sha256 {
                if try await verifySHA256(url: destinationURL, expected: hash) {
                    currentProgress.statusMessage = "File already downloaded and verified"
                    progressHandler?(currentProgress)
                    SystemLog().logEvent(event: "[GoogleDriveDownloader] File already exists: \(task.fileName)")
                    return destinationURL
                } else {
                    // ハッシュ不一致 → 削除して再ダウンロード
                    try? FileManager.default.removeItem(at: destinationURL)
                    SystemLog().logEvent(event: "[GoogleDriveDownloader] Hash mismatch, re-downloading: \(task.fileName)")
                }
            } else {
                currentProgress.statusMessage = "File already exists (no verification)"
                progressHandler?(currentProgress)
                return destinationURL
            }
        }

        // 部分ダウンロードから再開
        let resumeOffset: UInt64
        if FileManager.default.fileExists(atPath: partialURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: partialURL.path),
           let size = attrs[.size] as? UInt64 {
            resumeOffset = size
            SystemLog().logEvent(event: "[GoogleDriveDownloader] Resuming from \(resumeOffset) bytes")
        } else {
            resumeOffset = 0
        }

        // Google Drive Direct Download URL
        let downloadURL = URL(string: "https://drive.google.com/uc?export=download&id=\(task.fileId)")!

        var request = URLRequest(url: downloadURL)
        request.timeoutInterval = 300 // 5分タイムアウト

        if resumeOffset > 0 {
            request.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
        }

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 206 else {
            SystemLog().logEvent(event: "[GoogleDriveDownloader] HTTP error \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }

        // ストリーミング書き込み
        let fileHandle: FileHandle
        if FileManager.default.fileExists(atPath: partialURL.path) && resumeOffset > 0 {
            fileHandle = try FileHandle(forWritingTo: partialURL)
            try fileHandle.seekToEnd()
        } else {
            FileManager.default.createFile(atPath: partialURL.path, contents: nil)
            fileHandle = try FileHandle(forWritingTo: partialURL)
        }

        defer { try? fileHandle.close() }

        var downloadedBytes: UInt64 = resumeOffset
        let contentLength = httpResponse.expectedContentLength > 0 ? UInt64(httpResponse.expectedContentLength) : 0
        let totalBytes = task.expectedSizeBytes ?? (contentLength > 0 ? contentLength + resumeOffset : 0)

        currentProgress.totalBytes = totalBytes
        currentProgress.downloadedBytes = downloadedBytes

        var buffer = Data()
        buffer.reserveCapacity(1_048_576) // 1MB buffer

        for try await byte in asyncBytes {
            buffer.append(byte)

            // 1MBごとにディスクへ書き込み + 進捗更新
            if buffer.count >= 1_048_576 {
                try fileHandle.write(contentsOf: buffer)
                downloadedBytes += UInt64(buffer.count)
                buffer.removeAll(keepingCapacity: true)

                currentProgress.downloadedBytes = downloadedBytes
                currentProgress.statusMessage = String(format: "Downloading: %.1f%%", currentProgress.percentage * 100)
                progressHandler?(currentProgress)
            }
        }

        // 残りのバッファを書き込み
        if !buffer.isEmpty {
            try fileHandle.write(contentsOf: buffer)
            downloadedBytes += UInt64(buffer.count)
        }

        currentProgress.downloadedBytes = downloadedBytes
        currentProgress.statusMessage = "Download complete, verifying..."
        progressHandler?(currentProgress)

        SystemLog().logEvent(event: "[GoogleDriveDownloader] Downloaded \(downloadedBytes) bytes")

        // 完了後にリネーム
        try FileManager.default.moveItem(at: partialURL, to: destinationURL)

        // SHA256検証
        if let hash = task.sha256 {
            currentProgress.statusMessage = "Verifying SHA256..."
            progressHandler?(currentProgress)

            guard try await verifySHA256(url: destinationURL, expected: hash) else {
                try FileManager.default.removeItem(at: destinationURL)
                SystemLog().logEvent(event: "[GoogleDriveDownloader] SHA256 verification failed")
                throw URLError(.cannotDecodeContentData)
            }

            SystemLog().logEvent(event: "[GoogleDriveDownloader] SHA256 verification passed")
        }

        currentProgress.statusMessage = "Complete"
        progressHandler?(currentProgress)

        return destinationURL
    }

    /// SHA256ハッシュ検証（大規模ファイル対応）
    private func verifySHA256(url: URL, expected: String) async throws -> Bool {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1MB chunks

        while true {
            let data = fileHandle.readData(ofLength: bufferSize)
            if data.isEmpty { break }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        let computedHex = digest.map { String(format: "%02x", $0) }.joined()

        return computedHex.lowercased() == expected.lowercased()
    }

    /// 現在の進捗を取得
    func getProgress() -> DownloadProgress {
        return currentProgress
    }
}
