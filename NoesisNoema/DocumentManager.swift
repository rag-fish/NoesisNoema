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
    @Published var ragpackChunks: [String: [Chunk]] = [:]
    let historyKey = "RAGpackUploadHistory"
    let ragpackChunksKey = "RAGpackChunks"

    /**
     * Initializes a DocumentManager with an empty array of LLMRagFiles.
     * This is the default initializer that sets up the document manager for use.
     */
    init() {
        self.llmragFiles = []
        loadHistory()
        loadRAGpackChunks()
    }

    func saveHistory() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(uploadHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
    func loadHistory() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let history = try? decoder.decode([UploadHistory].self, from: data) {
            uploadHistory = history
        }
    }
    func saveRAGpackChunks() {
        let encoder = JSONEncoder()
        let dict = ragpackChunks.mapValues { chunks in
            try? encoder.encode(chunks)
        }
        UserDefaults.standard.set(dict, forKey: ragpackChunksKey)
    }
    func loadRAGpackChunks() {
        let decoder = JSONDecoder()
        if let dict = UserDefaults.standard.dictionary(forKey: ragpackChunksKey) as? [String: Data] {
            ragpackChunks = dict.compactMapValues { data in
                (try? decoder.decode([Chunk].self, from: data)) ?? []
            }
        }
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
    func importDocument(file: Any) {
        guard let fileURL = file as? URL else {
            print("Error: Provided file is not a URL.")
            return
        }
        guard fileURL.pathExtension.lowercased() == "zip" else {
            print("Error: Only .zip RAGpack files can be imported.")
            return
        }
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
                    _ = try archive.extract(entry, to: destinationURL)
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
            let chunks = zip(chunkStrings, embeddings).map { Chunk(content: $0.0, embedding: $0.1) }
            var metadata: [String: Any] = [:]
            if fileManager.fileExists(atPath: metadataURL.path) {
                let metadataData = try Data(contentsOf: metadataURL)
                if let meta = try JSONSerialization.jsonObject(with: metadataData, options: []) as? [String: Any] {
                    metadata = meta
                }
            }
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            let timestamp = Date()
            let docName = "\(baseName)_\(Int(timestamp.timeIntervalSince1970))"
            let ragFile = LLMRagFile(filename: docName, metadata: metadata, chunks: chunks)
            self.llmragFiles.append(ragFile)
            print("Imported RAGpack document: \(docName)")
            let uniqueChunks = chunks.filter { chunk in
                !VectorStore.shared.chunks.contains(where: { $0.content == chunk.content && $0.embedding == chunk.embedding })
            }
            DispatchQueue.main.async {
                VectorStore.shared.chunks.append(contentsOf: uniqueChunks)
                print("RAGpack unique chunks added to VectorStore.shared (RAG検索対象拡張)")
            }
            ragpackChunks[docName] = uniqueChunks
            uploadHistory.append(UploadHistory(filename: docName, timestamp: timestamp, chunkCount: uniqueChunks.count))
            self.saveHistory()
            self.saveRAGpackChunks()
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
                        let response: String = await llama.complete(text: prompt)
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
}
