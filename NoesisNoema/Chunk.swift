// Project: NoesisNoema
// File: Chunk.swift
// Created by Раскольников on 2025/07/20.
// Description: Defines the Chunk class for handling text chunks with embeddings.
// License: MIT License


import Foundation

class Chunk {

    /**
        * Represents a text chunk with its content, embedding, and metadata.
        * - Properties:
        *   - content: The text content of the chunk.
        *   - embedding: The embedding vector for the chunk, typically a list of floats.
        *   - metadata: Additional metadata associated with the chunk, such as source, timestamp,
        *     or any other relevant information.
        * - Initializer: Initializes a Chunk with the specified content, embedding, and optional metadata.
        */
    var content: String
    
    /**
        * The embedding vector for the chunk.
        * This is typically a list of floats representing the semantic meaning of the content.
        * It is used for similarity search and other operations that require understanding the
        * context of the text.
        */
    var embedding: [Float]

    /**
        * Additional metadata associated with the chunk.
        * This can include information such as source, timestamp, or any other relevant details
        * that provide context for the chunk.
        */
    var metadata: [String: Any]

    /**
        * Initializes a Chunk with the specified content, embedding, and optional metadata.
        */
    init(content: String, embedding: [Float], metadata: [String: Any] = [:]) {
        self.content = content
        self.embedding = embedding
        self.metadata = metadata
    }

}
