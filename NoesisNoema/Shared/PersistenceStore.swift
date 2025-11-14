//
//  PersistenceStore.swift
//  NoesisNoema
//
//  Created: 2025-11-14
//  Purpose: File-based storage for large data to avoid UserDefaults 4MB limit
//

import Foundation

/// Safe wrapper for UserDefaults writes with size limit enforcement
private let kMaxUserDefaultsSize = 4 * 1024 * 1024 // 4MB hard limit

func nn_safeSet(_ value: Data, forKey key: String, defaults: UserDefaults = .standard) {
    if value.count >= kMaxUserDefaultsSize {
        NSLog("[NoesisNoema] ⚠️ SKIPPED UserDefaults key '%@': %d bytes (>= 4MB limit)", key, value.count)
        return
    }
    defaults.set(value, forKey: key)
}

func nn_safeSet(_ value: String, forKey key: String, defaults: UserDefaults = .standard) {
    let byteCount = value.utf8.count
    if byteCount >= kMaxUserDefaultsSize {
        NSLog("[NoesisNoema] ⚠️ SKIPPED UserDefaults key '%@': %d bytes (>= 4MB limit)", key, byteCount)
        return
    }
    defaults.set(value, forKey: key)
}

// MARK: - File-Based Storage for Large Data

/// Manages file-based persistence for large conversation and RAG data
final class PersistenceStore {
    static let shared = PersistenceStore()

    private let fileManager: FileManager
    private let baseDirectory: URL

    // File paths
    private var qaHistoryFileURL: URL { baseDirectory.appendingPathComponent("qaHistory.json") }
    private var ragpackChunksFileURL: URL { baseDirectory.appendingPathComponent("ragpackChunks.json") }
    private var uploadHistoryFileURL: URL { baseDirectory.appendingPathComponent("uploadHistory.json") }

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        // Get Application Support directory
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not locate Application Support directory")
        }

        // Create NoesisNoema subdirectory
        self.baseDirectory = appSupport.appendingPathComponent("NoesisNoema", isDirectory: true)

        // Ensure directory exists
        do {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true, attributes: nil)
            NSLog("[PersistenceStore] ✅ Storage directory: %@", baseDirectory.path)
        } catch {
            NSLog("[PersistenceStore] ❌ Failed to create storage directory: %@", error.localizedDescription)
        }
    }

    // MARK: - QA History (LARGE PAYLOAD - questions + answers)

    func saveQAHistory(_ history: [QAPair]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(history)
            let sizeMB = Double(data.count) / (1024 * 1024)

            // Sanity check: warn if file is getting huge (> 32MB)
            if data.count > 32 * 1024 * 1024 {
                NSLog("[PersistenceStore] ⚠️ QA History file is very large: %.2f MB", sizeMB)
            }

            try data.write(to: qaHistoryFileURL, options: [.atomic])
            NSLog("[PersistenceStore] ✅ Saved QA History: %.2f MB, %d items", sizeMB, history.count)
        } catch {
            NSLog("[PersistenceStore] ❌ Failed to save QA History: %@", error.localizedDescription)
        }
    }

    func loadQAHistory() -> [QAPair] {
        guard fileManager.fileExists(atPath: qaHistoryFileURL.path) else {
            NSLog("[PersistenceStore] ℹ️ No QA History file found (first launch)")
            return []
        }

        do {
            let data = try Data(contentsOf: qaHistoryFileURL)
            let decoder = JSONDecoder()
            let history = try decoder.decode([QAPair].self, from: data)
            let sizeMB = Double(data.count) / (1024 * 1024)
            NSLog("[PersistenceStore] ✅ Loaded QA History: %.2f MB, %d items", sizeMB, history.count)
            return history
        } catch {
            NSLog("[PersistenceStore] ❌ Failed to load QA History: %@", error.localizedDescription)
            return []
        }
    }

    // MARK: - RAGpack Chunks (LARGE PAYLOAD - embeddings + content)

    func saveRAGpackChunks(_ chunks: [String: [Chunk]]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(chunks)
            let sizeMB = Double(data.count) / (1024 * 1024)

            // Sanity check
            if data.count > 32 * 1024 * 1024 {
                NSLog("[PersistenceStore] ⚠️ RAGpack Chunks file is very large: %.2f MB", sizeMB)
            }

            try data.write(to: ragpackChunksFileURL, options: [.atomic])
            NSLog("[PersistenceStore] ✅ Saved RAGpack Chunks: %.2f MB, %d packs", sizeMB, chunks.count)
        } catch {
            NSLog("[PersistenceStore] ❌ Failed to save RAGpack Chunks: %@", error.localizedDescription)
        }
    }

    func loadRAGpackChunks() -> [String: [Chunk]] {
        guard fileManager.fileExists(atPath: ragpackChunksFileURL.path) else {
            NSLog("[PersistenceStore] ℹ️ No RAGpack Chunks file found (first launch)")
            return [:]
        }

        do {
            let data = try Data(contentsOf: ragpackChunksFileURL)
            let decoder = JSONDecoder()
            let chunks = try decoder.decode([String: [Chunk]].self, from: data)
            let sizeMB = Double(data.count) / (1024 * 1024)
            NSLog("[PersistenceStore] ✅ Loaded RAGpack Chunks: %.2f MB, %d packs", sizeMB, chunks.count)
            return chunks
        } catch {
            NSLog("[PersistenceStore] ❌ Failed to load RAGpack Chunks: %@", error.localizedDescription)
            return [:]
        }
    }

    // MARK: - Upload History (SMALL - safe for UserDefaults or file)

    func saveUploadHistory(_ history: [DocumentManager.UploadHistory]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(history)
            let sizeMB = Double(data.count) / (1024 * 1024)

            // This should be small, but use file storage for consistency
            try data.write(to: uploadHistoryFileURL, options: [.atomic])
            NSLog("[PersistenceStore] ✅ Saved Upload History: %.2f MB, %d items", sizeMB, history.count)
        } catch {
            NSLog("[PersistenceStore] ❌ Failed to save Upload History: %@", error.localizedDescription)
        }
    }

    func loadUploadHistory() -> [DocumentManager.UploadHistory] {
        guard fileManager.fileExists(atPath: uploadHistoryFileURL.path) else {
            NSLog("[PersistenceStore] ℹ️ No Upload History file found (first launch)")
            return []
        }

        do {
            let data = try Data(contentsOf: uploadHistoryFileURL)
            let decoder = JSONDecoder()
            let history = try decoder.decode([DocumentManager.UploadHistory].self, from: data)
            NSLog("[PersistenceStore] ✅ Loaded Upload History: %d items", history.count)
            return history
        } catch {
            NSLog("[PersistenceStore] ❌ Failed to load Upload History: %@", error.localizedDescription)
            return []
        }
    }

    // MARK: - Migration from UserDefaults

    /// Migrates large data from UserDefaults to file storage (one-time operation)
    func migrateFromUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        var migrationPerformed = false

        // Check if migration already done
        if defaults.bool(forKey: "NN_MigrationCompleted_v1") {
            NSLog("[PersistenceStore] ℹ️ Migration already completed")
            return
        }

        NSLog("[PersistenceStore] 🔄 Starting UserDefaults → File migration...")

        // Migrate QA History
        if let qaData = defaults.data(forKey: "QAHistory") {
            let sizeMB = Double(qaData.count) / (1024 * 1024)
            NSLog("[PersistenceStore] Found QA History in UserDefaults: %.2f MB", sizeMB)

            if qaData.count < kMaxUserDefaultsSize {
                do {
                    let decoder = JSONDecoder()
                    let history = try decoder.decode([QAPair].self, from: qaData)
                    saveQAHistory(history)
                    defaults.removeObject(forKey: "QAHistory")
                    migrationPerformed = true
                    NSLog("[PersistenceStore] ✅ Migrated QA History to file")
                } catch {
                    NSLog("[PersistenceStore] ⚠️ Failed to decode QA History: %@", error.localizedDescription)
                }
            } else {
                NSLog("[PersistenceStore] ⚠️ QA History in UserDefaults is >= 4MB, discarding")
                defaults.removeObject(forKey: "QAHistory")
            }
        }

        // Migrate RAGpack Chunks
        if let chunksDict = defaults.dictionary(forKey: "RAGpackChunks") as? [String: Data] {
            NSLog("[PersistenceStore] Found RAGpack Chunks in UserDefaults")
            let decoder = JSONDecoder()
            var migratedChunks: [String: [Chunk]] = [:]

            for (key, data) in chunksDict {
                let sizeMB = Double(data.count) / (1024 * 1024)
                if data.count < kMaxUserDefaultsSize {
                    if let chunks = try? decoder.decode([Chunk].self, from: data) {
                        migratedChunks[key] = chunks
                        NSLog("[PersistenceStore] Migrated RAGpack '%@': %.2f MB", key, sizeMB)
                    }
                } else {
                    NSLog("[PersistenceStore] ⚠️ RAGpack '%@' is >= 4MB, discarding", key)
                }
            }

            if !migratedChunks.isEmpty {
                saveRAGpackChunks(migratedChunks)
                migrationPerformed = true
            }
            defaults.removeObject(forKey: "RAGpackChunks")
            NSLog("[PersistenceStore] ✅ Migrated RAGpack Chunks to file")
        }

        // Mark migration complete
        defaults.set(true, forKey: "NN_MigrationCompleted_v1")

        if migrationPerformed {
            NSLog("[PersistenceStore] ✅ Migration complete - large data removed from UserDefaults")
        } else {
            NSLog("[PersistenceStore] ℹ️ No data to migrate")
        }
    }
}
