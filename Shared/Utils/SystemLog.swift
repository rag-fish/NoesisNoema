// Project: NoesisNoema
// File: SystemLog.swift
// Created by Раскольников on 2025/07/20.
// Description: Defines the SystemLog class for logging system events.
// License: MIT License


import Foundation

/**
    * SystemLog provides file-based logging of system events.
    * - Features:
    *   - Logs events with timestamps to a persistent file in the user's Documents directory.
    *   - Prints an error to the console if file writing fails.
    *   - Allows retrieval of the current log file contents for auditing or review.
    */
class SystemLog {
    /// The URL of the persistent log file (in the user's Documents directory, named "NoesisNoema_system.log")
    let logFileURL: URL

    /// ログファイルの最大サイズ（例: 10MB）
    private let maxLogFileSize: UInt64 = 10 * 1024 * 1024

    /**
        * Initializes the SystemLog and sets up the log file path.
        * The log file is stored in the user's Documents directory as "NoesisNoema_system.log".
        */
    @discardableResult
    init() {
        // Determine the user's Documents directory and set the log file URL
        let fileManager = FileManager.default
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            self.logFileURL = docs.appendingPathComponent("NoesisNoema_system.log")
        } else {
            // Fallback: use temporary directory if Documents not found
            self.logFileURL = fileManager.temporaryDirectory.appendingPathComponent("NoesisNoema_system.log")
        }
    }

    /**
        * Logs an event message with a timestamp to the persistent log file.
        * If file writing fails, prints an error message to the console.
        * - Parameter event: The event message to be logged.
        */
    func logEvent(event: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] \(event)\n"
        let data = logLine.data(using: .utf8)!
        let fileManager = FileManager.default
        do {
            // ログファイルサイズが最大値を超えたらローテート
            if fileManager.fileExists(atPath: logFileURL.path) {
                let attrs = try fileManager.attributesOfItem(atPath: logFileURL.path)
                if let fileSize = attrs[.size] as? UInt64, fileSize > maxLogFileSize {
                    let backupURL = logFileURL.deletingPathExtension().appendingPathExtension("bak")
                    try? fileManager.removeItem(at: backupURL)
                    try fileManager.moveItem(at: logFileURL, to: backupURL)
                }
            }
            // 追記 or 新規作成
            if fileManager.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    defer { fileHandle.closeFile() }
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                } else {
                    print("SystemLog ERROR: Could not open log file for writing at \(logFileURL.path)")
                }
            } else {
                try data.write(to: logFileURL, options: .atomic)
            }
        } catch {
            print("SystemLog ERROR: Failed to write event to log file (\(error))")
        }
    }

    /**
        * Retrieves the contents of the log file as a string.
        * - Returns: The contents of the log file, or nil if reading fails.
        */
    func getLogContents() -> String? {
        do {
            let contents = try String(contentsOf: logFileURL, encoding: .utf8)
            return contents
        } catch {
            print("SystemLog ERROR: Failed to read log file (\(error))")
            return nil
        }
    }
}
