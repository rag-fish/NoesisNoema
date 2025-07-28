//// VectorStore.swift
/// //  NoesisNoema
/// //  Created by Раскольников on 2025/07/18.


import Foundation

class VectorStore {
    
    /**
        A structure representing a chunk of text with its embedding.
        - `text`: The text content of the chunk.
        - `embedding`: The embedding vector for the text.
        - `metadata`: Optional metadata associated with the chunk.
     */
    var chunks: [Chunk]
    var embeddingModel: EmbeddingModel
    var isEmbedded: Bool
    /// Initializes a VectorStore with an embedding model and an optional initial set of chunks.
    /// - Parameters:
    ///  - embeddingModel: The model used to generate embeddings for text.
    init(embeddingModel: EmbeddingModel, chunks: [Chunk] = []) {
        self.embeddingModel = embeddingModel
        self.chunks = chunks
        self.isEmbedded = false
    }
        
    /**
        クエリ埋め込みベクトルに最も類似したChunkを返す
        - Parameter queryEmbedding: クエリの埋め込みベクトル（[Float]型）
        - Returns: 類似度上位のChunk配列
     */
    func findRelevant(queryEmbedding: [Float], topK: Int = 3) -> [Chunk] {
        // 類似度（コサイン類似度）計算
        func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
            let dot = zip(a, b).map(*).reduce(0, +)
            let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
            let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))
            return normA > 0 && normB > 0 ? dot / (normA * normB) : 0
        }
        // Chunkごとに類似度計算
        let scoredChunks = chunks.map { chunk in
            (chunk, cosineSimilarity(queryEmbedding, chunk.embedding))
        }
        // 類似度順にソートし、上位topK件を返す
        return scoredChunks.sorted { $0.1 > $1.1 }.prefix(topK).map { $0.0 }
    }
}
