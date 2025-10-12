// Project: NoesisNoema
// File: GoogleDriveService.swift
// Created by Раскольников on 2025/07/20.
// Description: Defines the GoogleDriveService class for handling Google Drive operations.
// License: MIT License

import Foundation

struct GoogleDriveFileMetadata {
    let id: String
    let name: String
    let size: Int64?
    let mimeType: String?
}

enum GoogleDriveError: Error, LocalizedError {
    case offline
    case notConfigured(reason: String)
    case invalidInput(message: String)
    case fileNotFound
    case permissionDenied
    case networkFailure(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .offline:
            return "App is in Offline mode. Please disable Offline to allow network access."
        case .notConfigured(let reason):
            return "Google Drive is not configured: \(reason)"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .fileNotFound:
            return "File not found on Google Drive."
        case .permissionDenied:
            return "Permission denied by Google Drive API."
        case .networkFailure(let underlying):
            return "Network failure: \(underlying.localizedDescription)"
        }
    }
}

class GoogleDriveService {
    private let log = SystemLog()

    // MARK: - Async, typed API (preferred)

    /// Uploads a FileResource to Google Drive and returns basic file metadata.
    @discardableResult
    func upload(_ resource: FileResource) async throws -> GoogleDriveFileMetadata {
        // オフラインガード
        try ConnectivityGuard.requireOnline()
        // ここで OAuth2 認証・Drive API 呼び出しを行う想定
        // 現状は未設定の安全なスタブ
        log.logEvent(event: "[GoogleDriveService] upload called (filename=\(resource.filename), size=\(resource.data.count)) but Drive is not configured.")
        throw GoogleDriveError.notConfigured(reason: "OAuth2 client and Drive SDK are not integrated yet.")
    }

    /// Downloads file data by Drive file ID.
    func download(fileId: String) async throws -> Data {
        try ConnectivityGuard.requireOnline()
        log.logEvent(event: "[GoogleDriveService] download called (fileId=\(fileId)) but Drive is not configured.")
        throw GoogleDriveError.notConfigured(reason: "OAuth2 client and Drive SDK are not integrated yet.")
    }

    /// Lists files and returns (items, nextPageToken) tuple.
    func listFiles(pageToken: String? = nil, pageSize: Int = 50) async throws -> ([GoogleDriveFileMetadata], String?) {
        try ConnectivityGuard.requireOnline()
        log.logEvent(event: "[GoogleDriveService] listFiles called (pageSize=\(pageSize), pageToken=\(pageToken ?? "nil")) but Drive is not configured.")
        throw GoogleDriveError.notConfigured(reason: "OAuth2 client and Drive SDK are not integrated yet.")
    }

    // MARK: - Legacy wrappers (keep existing signature; non-blocking, logs only)

    /**     * Uploads a file to Google Drive.
        * - Parameter file: The file to be uploaded, which can be of any type.
        * - Note: This method should handle the authentication and upload process to Google Drive.
        */
    func upload(file: Any) -> Void {
        if !ConnectivityGuard.canPerformRemoteCall() {
            let msg = "[GoogleDriveService] Offline: Remote calls are disabled. Enable Offline toggle to allow network access."
            print(msg)
            log.logEvent(event: msg)
            return
        }
        // サポートする代表的な入力だけ扱い、残りは不正入力としてログ
        if let fr = file as? FileResource {
            Task { [log] in
                do {
                    _ = try await upload(fr)
                } catch {
                    log.logEvent(event: "[GoogleDriveService] upload(file: Any) failed: \(error.localizedDescription)")
                }
            }
        } else if let data = file as? Data {
            let fr = FileResource(filename: "untitled", data: data)
            Task { [log] in
                do {
                    _ = try await upload(fr)
                } catch {
                    log.logEvent(event: "[GoogleDriveService] upload(Data) failed: \(error.localizedDescription)")
                }
            }
        } else {
            let msg = "[GoogleDriveService] upload(file:) unsupported input type: \(type(of: file))"
            print(msg)
            log.logEvent(event: msg)
        }
    }


    /**
        * Downloads a file from Google Drive.
        * - Parameter filename: The name of the file to be downloaded, which can be of any type.
        * - Note: This method should handle the authentication and retrieval of the file from Google Drive.
        */
    func download(filename: Any) -> Void {
        if !ConnectivityGuard.canPerformRemoteCall() {
            let msg = "[GoogleDriveService] Offline: Remote calls are disabled. Enable Offline toggle to allow network access."
            print(msg)
            log.logEvent(event: msg)
            return
        }
        // レガシー仕様は不明瞭なので、ファイルID(String)のみ暫定対応
        if let fileId = filename as? String {
            Task { [log] in
                do {
                    _ = try await download(fileId: fileId)
                } catch {
                    log.logEvent(event: "[GoogleDriveService] download(filename:) failed: \(error.localizedDescription)")
                }
            }
        } else {
            let msg = "[GoogleDriveService] download(filename:) unsupported input type: \(type(of: filename))"
            print(msg)
            log.logEvent(event: msg)
        }
    }

    /**
        * Lists files in Google Drive.
        * - Note: This method should retrieve and return a list of files available in Google Drive.
        */
    func listFiles() -> Void {
        if !ConnectivityGuard.canPerformRemoteCall() {
            let msg = "[GoogleDriveService] Offline: Remote calls are disabled. Enable Offline toggle to allow network access."
            print(msg)
            log.logEvent(event: msg)
            return
        }
        Task { [log] in
            do {
                _ = try await listFiles(pageToken: nil, pageSize: 50)
            } catch {
                log.logEvent(event: "[GoogleDriveService] listFiles() failed: \(error.localizedDescription)")
            }
        }
    }
}
