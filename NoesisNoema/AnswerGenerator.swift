// Created by NoesisNoema on 2024/01/01.
// License: MIT License
// Project: NoesisNoema
// Description: Defines the AnswerGenerator class for generating answers from chunks and queries.
//

import Foundation

class AnswerGenerator {
    var embeddingModel: EmbeddingModel
    var vectorStore: VectorStore
    var llmModel: LLMModel
    
    init(embeddingModel: EmbeddingModel, vectorStore: VectorStore, llmModel: LLMModel) {
        self.embeddingModel = embeddingModel
        self.vectorStore = vectorStore
        self.llmModel = llmModel
    }
    /**
     * Generates an answer based on the provided chunks and query.
     * - Parameters:
     *   - chunks: An array of Chunk objects representing the data to be processed.
     *   - query: A string representing the user's query.
     * - Returns: An Answer object containing the generated answer.
     */
    func generate(chunks: [Chunk], query: String) -> Answer {
        // 1. クエリをベクトル化
        let queryEmbedding = embeddingModel.embed(text: query)
        // 2. 類似Chunk検索
        let relevantChunks = vectorStore.findRelevant(queryEmbedding: queryEmbedding)
        // 3. 関連Chunkの内容をまとめる
        let context = relevantChunks.map { $0.content }.joined(separator: "\n")
        // 4. LLMにプロンプトとして渡す
        let prompt = "質問: \(query)\n文脈:\n\(context)"
        let response = llmModel.generate(prompt: prompt)
        // 5. スコア計算（例: 最初のChunkとの類似度を使う）
        let score: Float = relevantChunks.first?.embedding.enumerated().reduce(0) { $0 + Float(queryEmbedding[$1.offset]) * $1.element } ?? 0.0
        // 6. Answer生成
        let metadata: [String: Any] = ["chunks": relevantChunks.map { $0.content }]
        return Answer(text: response, score: score, metadata: metadata)
    }
}
