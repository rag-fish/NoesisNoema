//
//  FileTraceSink.swift
//  NoesisNoema
//
//  Purpose: JSONL-based file storage for execution traces
//  License: MIT License
//

import Foundation

/// File-based trace sink using JSONL format (one JSON object per line)
/// Actor ensures thread-safe, serialized access to the trace file
actor FileTraceSink: TraceSink {

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let fileManager = FileManager.default

    /// Initialize with default trace file location
    init() {
        // Create traces file at ~/Library/Application Support/NoesisNoema/traces.jsonl
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let noesisDir = appSupport.appendingPathComponent("NoesisNoema", isDirectory: true)

        // Ensure directory exists
        try? fileManager.createDirectory(at: noesisDir, withIntermediateDirectories: true)

        self.fileURL = noesisDir.appendingPathComponent("traces.jsonl")

        // Configure encoder for compact output
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = []
    }

    /// Write a trace to the JSONL file (append-only)
    func write(trace: ExecutionTrace) async {
        do {
            // Encode trace to JSON
            let jsonData = try encoder.encode(trace)

            // Convert to string and append newline
            guard var jsonString = String(data: jsonData, encoding: .utf8) else {
                return
            }
            jsonString += "\n"

            // Append to file
            if let data = jsonString.data(using: .utf8) {
                if fileManager.fileExists(atPath: fileURL.path) {
                    // Append to existing file
                    if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        try? fileHandle.close()
                    }
                } else {
                    // Create new file
                    try? data.write(to: fileURL, options: .atomic)
                }
            }
        } catch {
            // Silent failure - tracing should not crash the app
            // In production, this could log to system logger
        }
    }

    /// Read traces from the JSONL file
    /// - Parameter limit: Maximum number of traces to return (most recent)
    /// - Returns: Array of execution traces
    /// - Throws: IO or decoding errors
    func read(limit: Int) async throws -> [ExecutionTrace] {
        // File not existing is not an error - just means no traces yet
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        // Read file contents - may throw
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.components(separatedBy: .newlines)

        // Decode line by line (last N lines)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var traces: [ExecutionTrace] = []

        // Process lines in reverse to get most recent first
        let relevantLines = lines.reversed().prefix(limit)

        for line in relevantLines {
            guard !line.isEmpty else { continue }

            if let data = line.data(using: .utf8) {
                // May throw decoding error
                let trace = try decoder.decode(ExecutionTrace.self, from: data)
                traces.append(trace)
            }
        }

        // Return in chronological order (oldest first)
        return traces.reversed()
    }
}
