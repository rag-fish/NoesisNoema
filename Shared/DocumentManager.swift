// Project: NoesisNoema
// File: DocumentManager.swift
// Created by Раскольников on 2025/07/20.
// Description: Manages document imports and interactions with LLMRag files.
// License: MIT License
//


import Foundation
import SwiftUI
import Combine
import ZIPFoundation

/**
 * Represents a document manager that handles the import and management of .zip RAGpack files.
 * - Properties:
 *   - llmragFiles: An array of LLMRagFile objects representing the RAGpack files managed by the document manager.
 * - Methods:
 *   - importDocument(file: Any): Imports a document from a .zip RAGpack file.
 *   - loadFromGoogleDrive(file: Any): Loads a RAGpack document from Google Drive (RAGpack-based architecture).
 *   - importTokenizerArchive(file: Any): (DEPRECATED) Tokenizer archives are no longer used; RAGpack .zip files are now standard.
 *   - importModelResource(file: Any): Imports a model resource (architecture now expects RAGpack files).
 *   - QA History Management:
 *       - addQAPair(question:answer:): Adds a new QA pair to history and selects it.
 *       - selectQAPair(_:): Selects a given QA pair.
 *       - deleteQAPair(at:): Deletes QA pairs at specified offsets.
 *       - clearQAHistroy(): Clears all QA history and selection.
 */

class DocumentManager: ObservableObject {
    /**
     * An array of LLMRagFile objects representing the files managed by the document manager.
     * This array contains all the RAGpack files (.zip) that have been imported or loaded into the system.
     */
    struct UploadHistory: Codable, Identifiable {
        var id: String { filename }
        let filename: String
        let timestamp: Date
        let chunkCount: Int
    }
    @Published var llmragFiles: [LLMRagFile]
    @Published var uploadHistory: [UploadHistory] = []

    /// POTENTIAL LARGE PAYLOAD: RAGpack chunks with embeddings (can be MBs per pack)
    @Published var ragpackChunks: [String: [Chunk]] = [:]

    /// ADR-0011 §4 (no silent fallback): the last RAGpack import failure, surfaced
    /// to the user via a SwiftUI alert in the Settings views. Set on a failed
    /// import; cleared on a successful one (and when the user dismisses the alert).
    @Published var lastImportError: RAGpackImportError? = nil

    /// The app's current query/pack embedder — reused from the shared VectorStore
    /// so we don't reload the GGUF. Drives the v1.2 manifest fingerprint/dimension
    /// validation (ADR-0011 §3).
    private var embedder: EmbeddingModel { VectorStore.shared.embeddingModel }

    // DEPRECATED: Old UserDefaults keys (migrated to file storage)
    // let historyKey = "RAGpackUploadHistory" // SMALL - but moved for consistency
    // let ragpackChunksKey = "RAGpackChunks"  // LARGE PAYLOAD - MOVED to file

    /// POTENTIAL LARGE PAYLOAD: QA history stores full questions + full answers
    /// Each answer can be hundreds of chars, × 100s of QA pairs = easily > 4MB
    @Published var qaHistory: [QAPair] = []

    /// Tracks the currently selected question-answer pair.
    @Published var selectedQAPair: QAPair? = nil

    // DEPRECATED: Old UserDefaults key
    // let qaHistoryKey = "QAHistory" // LARGE PAYLOAD - MOVED to file

    /**
     * Initializes a DocumentManager with an empty array of LLMRagFiles.
     * This is the default initializer that sets up the document manager for use.
     * Also loads upload history, RAGpack chunks, and QA history from persistent storage.
     *
     * ✅ NOW USES FILE-BASED STORAGE (not UserDefaults) for large data
     */
    init() {
        self.llmragFiles = []

        // Perform one-time migration from UserDefaults to file storage
        PersistenceStore.shared.migrateFromUserDefaultsIfNeeded()

        // Load from file storage
        loadHistory()
        loadRAGpackChunks()
        loadQAHistory()
    }

    // MARK: - Upload History (SMALL - moved to file for consistency)

    func saveHistory() {
        PersistenceStore.shared.saveUploadHistory(uploadHistory)
    }

    func loadHistory() {
        uploadHistory = PersistenceStore.shared.loadUploadHistory()
    }

    // MARK: - RAGpack Chunks (LARGE PAYLOAD - now in file storage)

    func saveRAGpackChunks() {
        PersistenceStore.shared.saveRAGpackChunks(ragpackChunks)
    }

    func loadRAGpackChunks() {
        ragpackChunks = PersistenceStore.shared.loadRAGpackChunks()
    }
    func deleteRAGpack(named name: String) {
        let chunksToDelete = ragpackChunks[name] ?? []
        ragpackChunks.removeValue(forKey: name)
        uploadHistory.removeAll { $0.filename == name }
        VectorStore.shared.chunks.removeAll { chunk in
            chunksToDelete.contains(where: { $0.content == chunk.content && $0.embedding == chunk.embedding })
        }
        saveHistory()
        saveRAGpackChunks()
    }

    /// Imports a document from a .zip RAGpack file.
    /// - Parameter file: The file to be imported (should be a .zip RAGpack).
    @MainActor
    func importDocument(file: Any) {
        guard let fileURL = file as? URL else {
            print("Error: Provided file is not a URL.")
            return
        }
        guard fileURL.pathExtension.lowercased() == "zip" else {
            print("Error: Only .zip RAGpack files can be imported.")
            return
        }

        // Clear any prior failure before starting a fresh import.
        self.lastImportError = nil

        // Run heavy processing off the main thread; route any failure to
        // `lastImportError` so the Settings views can present it (ADR-0011 §4).
        Task.detached {
            do {
                try await self.processRAGpackImport(fileURL: fileURL)
                await MainActor.run { self.lastImportError = nil }
            } catch {
                let importError = (error as? RAGpackImportError)
                    ?? .manifestMalformed(underlying: String(describing: error))
                print("[RAGpack import] failed: \(importError.errorDescription ?? "\(importError)")")
                await MainActor.run { self.lastImportError = importError }
            }
        }
    }

    /// Imports a RAGpack v1.2 archive (ADR-0011 §3-§7). Unzips, reads via
    /// `RAGpackReader` (which validates the manifest against the current embedder),
    /// and adds the chunks to the VectorStore. Throws `RAGpackImportError` on every
    /// malformation — no silent return, no v0.x CSV fallback.
    private func processRAGpackImport(fileURL: URL) async throws {
        // Sandboxed iOS AND macOS both require explicit security-scoped access for
        // user-picked URLs returned by .fileImporter / NSOpenPanel (PR #94 EPERM fix).
        var didStartAccessing = false
        #if os(iOS) || os(macOS)
        didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        if !didStartAccessing {
            print("Warning: Could not start accessing security-scoped resource for \(fileURL)")
        }
        defer {
            if didStartAccessing { fileURL.stopAccessingSecurityScopedResource() }
        }
        #endif

        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempDir) }

        // 1. Unzip into a temp dir. A zip that cannot be opened/extracted is not a
        //    readable v1.2 pack → surface as a missing-manifest failure.
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            let archive = try Archive(url: fileURL, accessMode: .read)
            for entry in archive {
                let destinationURL = tempDir.appendingPathComponent(entry.path)
                switch entry.type {
                case .directory:
                    try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
                default:
                    try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                    _ = try archive.extract(entry, to: destinationURL)
                }
            }
        } catch {
            throw RAGpackImportError.manifestMissing
        }

        // 2. Read + validate the v1.2 pack. Throws RAGpackImportError; let it propagate.
        let (chunks, _) = try RAGpackReader.readPack(at: tempDir, embedder: self.embedder)

        // 3. Title the chunks and add the unique ones to the VectorStore.
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let timestamp = Date()
        let docName = "\(baseName)_\(Int(timestamp.timeIntervalSince1970))"
        let titledChunks = chunks.map { ch -> Chunk in
            var c = ch
            if c.sourceTitle == nil { c.sourceTitle = docName }
            return c
        }
        let metadata: [String: Any] = [
            "pack_version": "1.2",
            "doc_name": docName
        ]
        let ragFile = LLMRagFile(filename: docName, metadata: metadata, chunks: titledChunks)

        let uniqueChunks = titledChunks.filter { chunk in
            !VectorStore.shared.chunks.contains(where: { $0.content == chunk.content && $0.embedding == chunk.embedding })
        }

        await MainActor.run {
            self.llmragFiles.append(ragFile)
            VectorStore.shared.chunks.append(contentsOf: uniqueChunks)
            self.ragpackChunks[docName] = uniqueChunks
            self.uploadHistory.append(UploadHistory(filename: docName, timestamp: timestamp, chunkCount: uniqueChunks.count))
            self.saveHistory()
            self.saveRAGpackChunks()
            print("Imported RAGpack v1.2 document: \(docName) (\(uniqueChunks.count) unique chunks)")
        }
    }

    /**
     * Loads a document from Google Drive.
     * - Parameter file: The file to be loaded, which can be of any type.
     * - Note: This method should handle the authentication and retrieval of a .zip RAGpack file from Google Drive.
     *       (TODO: Not implemented. Intended for RAGpack-based architecture.)
     */
    func loadFromGoogleDrive(file: Any) {
        // TODO: implement Google Drive RAGpack (.zip) import.
    }

    /**
     * (DEPRECATED) Imports a tokenizer archive from the specified file.
     * - Parameter file: The file containing the tokenizer archive, which can be of any type.
     * - Note: Tokenizer archives are deprecated; use RAGpack (.zip) files instead.
     *         (TODO: Not implemented. No longer required in RAGpack-based architecture.)
     */
    func importTokenizerArchive(file: Any) {
        // TODO: Deprecated. Tokenizers are managed within RAGpack (.zip) files.
    }

    /**
     * Imports a model resource from the specified file.
     * - Parameter file: The file containing the model resource, which can be of any type.
     * - Note: This method should handle the loading of a model resource, but RAGpack (.zip) files are now standard.
     *         (TODO: Not implemented. Intended for RAGpack-based architecture.)
     */
    func importModelResource(file: Any) {
        // TODO: implement model resource import for RAGpack-based architecture.
    }

    // MARK: - QA History Management

    /// Adds a new question-answer pair to the QA history and sets it as the selected pair.
    /// - Parameters:
    ///   - question: The question string.
    ///   - answer: The answer string.
    /// - Returns: The created QAPair.
    @discardableResult
    func addQAPair(question: String, answer: String) -> QAPair {
        let newPair = QAPair(question: question, answer: answer)
        qaHistory.append(newPair)
        selectedQAPair = newPair
        saveQAHistory()
        return newPair
    }

    /// Selects the specified QA pair.
    /// - Parameter pair: The QA pair to select.
    func selectQAPair(_ pair: QAPair) {
        selectedQAPair = pair
    }

    /// Deletes QA pairs at the specified offsets. If the deleted pair was selected, clears the selection.
    /// - Parameter offsets: The index set of QA pairs to delete.
    func deleteQAPair(at offsets: IndexSet) {
        for index in offsets {
            let pair = qaHistory[index]
            if pair == selectedQAPair {
                selectedQAPair = nil
            }
        }
        qaHistory.remove(atOffsets: offsets)
        saveQAHistory()
    }

    /// Clears all QA history and selection.
    func clearQAHistroy() {
        qaHistory.removeAll()
        selectedQAPair = nil
        saveQAHistory()
    }

    // MARK: - QA History (LARGE PAYLOAD - now in file storage)

    /// Saves the QA history to file storage (NOT UserDefaults).
    /// This prevents the 4MB limit issues.
    private func saveQAHistory() {
        PersistenceStore.shared.saveQAHistory(qaHistory)
    }

    /// Loads the QA history from file storage (NOT UserDefaults).
    private func loadQAHistory() {
        qaHistory = PersistenceStore.shared.loadQAHistory()
    }
}
