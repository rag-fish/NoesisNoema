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

        // Run heavy processing on background thread
        Task.detached {
            await self.processRAGpackImport(fileURL: fileURL)
        }
    }

    private func processRAGpackImport(fileURL: URL) async {
        // iOSのFiles/iCloud経由で選択されたURLに対しては、セキュリティスコープを開始する
        var didStartAccessing = false
        #if os(iOS)
        didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        if !didStartAccessing {
            print("Warning: Could not start accessing security-scoped resource for \(fileURL)")
        }
        defer {
            if didStartAccessing { fileURL.stopAccessingSecurityScopedResource() }
        }
        #elseif os(macOS)
        // NSOpenPanel + user-selected-file entitlement is sufficient; no scoped access required
        #endif
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            let archive: Archive
            do {
                archive = try Archive(url: fileURL, accessMode: .read)
            } catch {
                print("Error: Could not open ZIP archive. \(error)")
                try? fileManager.removeItem(at: tempDir)
                return
            }
            for entry in archive {
                let destinationURL = tempDir.appendingPathComponent(entry.path)
                do {
                    switch entry.type {
                    case .directory:
                        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
                        continue
                    default:
                        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                        _ = try archive.extract(entry, to: destinationURL)
                    }
                } catch {
                    print("Error extracting entry \(entry.path): \(error)")
                }
            }
        } catch {
            print("Error: Failed to create temporary directory or extract ZIP. \(error)")
            return
        }
        // Locate required files in the extracted directory
        let chunksURL = tempDir.appendingPathComponent("chunks.json")
        let embeddingsURL = tempDir.appendingPathComponent("embeddings.csv")
        let metadataURL = tempDir.appendingPathComponent("metadata.json")
        guard fileManager.fileExists(atPath: chunksURL.path),
              fileManager.fileExists(atPath: embeddingsURL.path) else {
            print("Error: Missing required file(s) in RAGpack (.zip): chunks.json and/or embeddings.csv.")
            try? fileManager.removeItem(at: tempDir)
            return
        }
        do {
            let chunksData = try Data(contentsOf: chunksURL)
            let chunkStrings = try JSONDecoder().decode([String].self, from: chunksData)
            let embeddingModel = EmbeddingModel(name: "import")
            let embeddings = embeddingModel.loadEmbeddingsCSV(from: embeddingsURL)
            if chunkStrings.count != embeddings.count {
                print("Error: chunks.jsonとembeddings.csvの数が一致しません")
                try? fileManager.removeItem(at: tempDir)
                return
            }
            let chunks = zip(chunkStrings, embeddings).map { Chunk(content: $0.0, embedding: $0.1, sourceTitle: nil, sourcePath: nil, page: nil) }
            // After building chunks, attach a default title so UI can show citations
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            let timestamp = Date()
            let docName = "\(baseName)_\(Int(timestamp.timeIntervalSince1970))"
            let titledChunks = chunks.map { ch -> Chunk in
                var c = ch
                c.sourceTitle = docName
                return c
            }
            var metadata: [String: Any] = [:]
            if fileManager.fileExists(atPath: metadataURL.path) {
                let metadataData = try Data(contentsOf: metadataURL)
                if let meta = try JSONSerialization.jsonObject(with: metadataData, options: []) as? [String: Any] {
                    metadata = meta
                }
            }
            let ragFile = LLMRagFile(filename: docName, metadata: metadata, chunks: titledChunks)

            // Filter unique chunks
            let uniqueChunks = titledChunks.filter { chunk in
                !VectorStore.shared.chunks.contains(where: { $0.content == chunk.content && $0.embedding == chunk.embedding })
            }

            // Update UI on main thread
            await MainActor.run {
                self.llmragFiles.append(ragFile)
                print("Imported RAGpack document: \(docName)")
                VectorStore.shared.chunks.append(contentsOf: uniqueChunks)
                print("RAGpack unique chunks added to VectorStore.shared (RAG検索対象拡張)")
                self.ragpackChunks[docName] = uniqueChunks
                self.uploadHistory.append(UploadHistory(filename: docName, timestamp: timestamp, chunkCount: uniqueChunks.count))
                self.saveHistory()
                self.saveRAGpackChunks()
            }
        } catch {
            print("Error: Failed to load chunks or embeddings. \(error)")
            try? fileManager.removeItem(at: tempDir)
            return
        }
        try? fileManager.removeItem(at: tempDir)
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

    /// モデルファイル探索＋LlamaStateでロード＋推論
    func inferWithLlama(prompt: String, fileName: String = "llama3-8b.gguf", completion: @escaping (String) -> Void) {
        // プレ・プロンプト（独白/CoT抑止）
        func buildPlainPrompt(question: String, context: String? = nil) -> String {
            let sys = """
            You are a helpful, concise assistant.
            Answer with the final answer only. Do not include analysis, chain-of-thought, self-talk, internal monologue, or meta commentary.
            Never output tags like <think>...</think>. If tempted, stop and give only the final answer.
            """
            var txt = sys + "\n\n"
            if let ctx = context, !ctx.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                txt += "Context:\n\(ctx)\n\n"
            }
            txt += "Question: \(question)\n\nAnswer:"
            return txt
        }
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        var checkedPaths: [String] = []
        let pathCWD = "\(cwd)/\(fileName)"
        checkedPaths.append(pathCWD)
        let exePath = CommandLine.arguments[0]
        let exeDir = URL(fileURLWithPath: exePath).deletingLastPathComponent().path
        let pathExeDir = "\(exeDir)/\(fileName)"
        if pathExeDir != pathCWD { checkedPaths.append(pathExeDir) }
        if let bundleResourceURL = Bundle.main.resourceURL {
            let pathBundle = bundleResourceURL.appendingPathComponent(fileName).path
            if pathBundle != pathCWD && pathBundle != pathExeDir { checkedPaths.append(pathBundle) }
        }
        for path in checkedPaths {
            if fm.fileExists(atPath: path) {
                print("[Llama] FOUND: \(path)")
                Task {
                    let llama = await LlamaState()
                    do {
                        try await llama.loadModel(modelUrl: URL(fileURLWithPath: path))
                        // プレ・プロンプト適用
                        let wrapped = buildPlainPrompt(question: prompt)
                        let response: String = await llama.complete(text: wrapped)
                        completion(response)
                    } catch {
                        print("[Llama] Error running inference: \(error)")
                        completion("[Llama Error] \(error)")
                    }
                }
                return
            }
        }
        print("[Llama] NOT FOUND in any attempted path!")
        completion("[Llama] Model file not found.")
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
