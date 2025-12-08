// Project: NoesisNoema
// File: EmbeddingModel.swift
// Created by Раскольников on 2025/07/20.
// Description: Defines the EmbeddingModel class for handling text embeddings.
// License: MIT License

import Foundation

class EmbeddingModel {

    /**
        * Represents an embedding model with its properties and methods.
        * - Properties:
        *   - name: The name of the embedding model.
        * - Methods:
        *   - embed(text: String) -> [Float]: Generates an embedding for the given text.
        *     This method takes a string input and returns an array of floats representing the embedding vector
        *     for the input text.
        */
    var name: String

    // PERFORMANCE: Cache embeddings to avoid recomputation
    private var embeddingCache: [String: [Float]] = [:]
    private let cacheQueue = DispatchQueue(label: "com.noesis.embedding.cache", attributes: .concurrent)
    private let maxCacheSize = 500

    init(name: String) {
        self.name = name
    }

    /// テキストを埋め込みベクトルに変換（キャッシュ付き）
    func embed(text: String) -> [Float] {
        // Check cache first
        let cached = cacheQueue.sync { embeddingCache[text] }
        if let cached = cached {
            return cached
        }

        // 1. テキストの文字コードの合計を計算
        let hashValue = text.unicodeScalars.reduce(0) { $0 + UInt32($1.value) }
        // 2. ダミーの埋め込みベクトルを生成（例: ハッシュ値を元に固定長のベクトルを作成）
        let embedding = (0..<10).map { i in
            Float((hashValue + UInt32(i * 31)) % 1000) / 1000.0
        }

        // Cache the result
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if self.embeddingCache.count >= self.maxCacheSize {
                let oldest = self.embeddingCache.keys.prefix(50)
                oldest.forEach { self.embeddingCache.removeValue(forKey: $0) }
            }
            self.embeddingCache[text] = embedding
        }

        // 3. 埋め込みベクトルを返す
        return embedding
    }

    /// embeddings.csvから[[Float]]としてロードする
    func loadEmbeddingsCSV(from url: URL) -> [[Float]] {
        do {
            let csvString = try String(contentsOf: url, encoding: .utf8)
            let rows = csvString.split(separator: "\n")
            let embeddings: [[Float]] = rows.map { row in
                row.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
            }
            return embeddings
        } catch {
            print("[EmbeddingModel] CSV読み込み失敗: \(error)")
            return []
        }
    }
}
