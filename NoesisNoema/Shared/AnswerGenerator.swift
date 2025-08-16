// Created by NoesisNoema on 2024/01/01.
// License: MIT License
// Project: NoesisNoema
// Description: Defines the AnswerGenerator class for generating answers from queries.
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
     * Generates an answer based on the provided query.
     * - Parameters:
     *   - query: A string representing the user's query.
     *   - topK: The number of top relevant chunks to consider. Default is 3.
     * - Returns: An Answer object containing the generated answer.
     */
    func generateAnswer(query: String, topK: Int = 3) -> Answer {
        let queryEmbedding = embedQuery(query)
        let relevantChunks = findRelevantChunks(queryEmbedding: queryEmbedding, topK: topK)
        let prompt = buildPrompt(query: query, chunks: relevantChunks)
        let response = llmModel.generate(prompt: prompt)
        // embeddingがないため、スコアは0.0固定
        let score: Float = 0.0
        let metadata: [String: Any] = ["chunks": relevantChunks.map { $0.content }]
        return Answer(text: response, score: score, metadata: metadata)
    }
    
    /// Embeds the query text into a vector representation.
    private func embedQuery(_ query: String) -> [Float] {
        return embeddingModel.embed(text: query)
    }
    
    /// Finds the most relevant chunks from the vector store based on the query embedding.
    private func findRelevantChunks(queryEmbedding: [Float], topK: Int) -> [Chunk] {
        return vectorStore.findRelevant(queryEmbedding: queryEmbedding, topK: topK)
    }
    
    /// Builds the prompt string to be sent to the language model.
    private func buildPrompt(query: String, chunks: [Chunk]) -> String {
        let context = chunks.map { $0.content }.joined(separator: "\n")
        return "Question: \(query)\nContext:\n\(context)"
    }
    
    /// Calculates a similarity score between the query embedding and a chunk embedding using dot product.
    private func scoreAnswer(queryEmbedding: [Float], chunkEmbedding: [Float]?) -> Float {
        // embeddingがないため常に0.0を返す
        return 0.0
    }
    
    /// Computes the dot product of two vectors.
    private func dotProduct(_ vectorA: [Float], _ vectorB: [Float]) -> Float {
        return zip(vectorA, vectorB).reduce(0) { $0 + $1.0 * $1.1 }
    }
}
