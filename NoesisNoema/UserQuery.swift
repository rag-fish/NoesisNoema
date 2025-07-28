// NoesisNoema is a knowledge graph framework for building AI applications.
// It provides a way to query and manage knowledge graphs using natural language.
// This file defines the UserQuery class for handling user queries.
// Created by NoesisNoema on 2024-02-24.
// License: MIT License
// Project: NoesisNoema

import Foundation

// UserQuery.swift
class UserQuery {
    
    /**
        Represents a user query in the NoesisNoema framework.
        This class is designed to handle user questions and generate responses
        using the knowledge graph, embedding models, and LLM models.
    */
    var question: String

    /**
        Initializes a UserQuery with the specified question.
        - Parameter question: The question to be asked by the user.
        - Note: This initializer sets the question property of the UserQuery instance.
        - Example:
        ```swift
        let userQuery = UserQuery(question: "What is the capital of France?")
        print(userQuery.question) // Prints "What is the capital of France?"
        ```
     */
    init(question: String) {
        self.question = question
    }
    
    /**
        Runs the query and returns an Answer object.
        This method should handle the logic for processing the user's question,
        including any necessary interactions with the knowledge graph, embedding models,
        and LLM models to generate a response.
        - Returns: An Answer object containing the response to the user's question.
        - Note: This method is currently a placeholder and needs to be implemented.
        - Example:
        ```swift
        let userQuery = UserQuery(question: "What is the capital of France?")
        let answer = userQuery.runQuery()
        print(answer.response) // Prints the answer to the question
        ```
     */
    func runQuery() -> Answer {
        // 実際のRAG型処理フローを実装
        // 1. 前処理（チャンク化）
        let preprocessor = Preprocessor()
        let chunks = preprocessor.preprocess(document: question)
        // 2. ベクトルストア構築
        let tokenizer = Tokenizer()
        let embeddingModel = EmbeddingModel(name: "default-embedding", tokenizer: tokenizer)
        let vectorStore = VectorStore(embeddingModel: embeddingModel, chunks: chunks)
        // 3. LLMモデル準備
        let llmModel = LLMModel(name: "default-llm", modelFile: "", version: "", tokenizer: tokenizer)
        // 4. AnswerGeneratorで回答生成
        let answerGenerator = AnswerGenerator(embeddingModel: embeddingModel, vectorStore: vectorStore, llmModel: llmModel)
        let answer = answerGenerator.generate(chunks: chunks, query: question)
        return answer
    }
    
}
