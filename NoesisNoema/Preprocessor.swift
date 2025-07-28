// NoesisNoema is a framework for building AI applications.
// It provides tools for managing knowledge graphs, embedding models, and LLM models.
// This file defines the Preprocessor class for handling text preprocessing.
// Created by NoesisNoema on 2024-02-24.

// License: MIT License
// Project: NoesisNoema

import Foundation

class Preprocessor {
    
    /**
        * Represents a preprocessor for handling text preprocessing tasks.
        * This class is designed to preprocess documents into chunks for further processing.
        * - Properties:
        *   - None
        * - Methods:
        *   - preprocess(document: Any) -> [Chunk]: Takes a document (of any type) and returns an array of Chunk objects.
        *     This method is responsible for breaking down the document into manageable chunks,
        *     which can then be used for embedding or other processing tasks.
        *     The document can be of any type, such as a string, file, or
        *     structured data, and the method should handle the conversion to text if necessary.
        *     - Parameter document: The document to be preprocessed, which can be of any
        *       type (e.g., string, file, structured data).
        *     - Returns: An array of Chunk objects representing the preprocessed document.
        *     - Note: This method is currently a placeholder and needs to be implemented.
        *     - Example:
        * ```swift
        * let preprocessor = Preprocessor()
        * let document = "This is a sample document to be preprocessed."
        * let chunks = preprocessor.preprocess(document: document)
        * print(chunks) // Prints the array of Chunk objects representing the preprocessed document.
        * ```
        */
    @discardableResult
    init() {}
    
    func preprocess(document: Any) -> [Chunk] {
        // 文字列以外はdescriptionで文字列化
        let text: String
        if let str = document as? String {
            text = str
        } else {
            text = String(describing: document)
        }
        // シンプルな文単位分割（ピリオド・改行で区切る）
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        // TokenizerとEmbeddingModelの仮インスタンス（実際はDIや外部注入が望ましい）
        let tokenizer = Tokenizer()
        let embeddingModel = EmbeddingModel(name: "default-embedding", tokenizer: tokenizer)
        // 各文をChunk化
        let chunks: [Chunk] = sentences.map { sentence in
            let embedding = embeddingModel.embed(text: sentence)
            return Chunk(content: sentence, embedding: embedding)
        }
        return chunks
    }
    
}
