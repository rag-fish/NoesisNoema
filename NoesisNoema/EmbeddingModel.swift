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
        *   - tokenizer: The tokenizer used by the model for processing text.
        * - Methods:
        *   - embed(text: String) -> [Float]: Generates an embedding for the given text.
        *     This method takes a string input and returns an array of floats representing the embedding vector
        *     for the input text.
        */
    var name: String
    
    
    var tokenizer: Tokenizer

    init(name: String, tokenizer: Tokenizer) {
        self.name = name
        self.tokenizer = tokenizer
    }
    
    /// テキストを埋め込みベクトルに変換
    func embed(text: String) -> [Float] {
        // 1. テキストをトークン化
        let tokens = tokenizer.encode(text: text)
        // 2. トークンIDを使って埋め込みベクトルを生成（例: 単純なID値をfloat化）
        // ※実際はモデル推論だが、ここではダミー実装
        let embedding = tokens.map { Float($0) }
        // 3. 埋め込みベクトルを返す
        return embedding
    }
    
}
