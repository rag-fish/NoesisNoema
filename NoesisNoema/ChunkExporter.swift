// Created by NoesisNoema on 2023/10/16.
// License: MIT License
// Project: NoesisNoema
// Description: Defines the ChunkExporter class for exporting chunks to an LLMRagFile.

import Foundation
import NoesisNoema

class ChunkExporter {
    
    
    var embeddingModel: EmbeddingModel
    var tokenizer: Tokenizer
    var llmModel: LLMModel
    var filename: String
    var metadata: [String: Any]
    var isEmbedded: Bool
    
    
    
    /// Initializes a ChunkExporter with the specified properties.
    /// - Parameters:
    /// - embeddingModel: The embedding model used for generating embeddings.
    /// - tokenizer: The tokenizer used for processing text.
    /// - llmModel: The large language model used for processing text.
    /// - filename: The name of the file to be exported.
    /// - metadata: A map containing metadata about the file.
    /// - isEmbedded: A boolean indicating if the file is embedded.
    init(embeddingModel: EmbeddingModel, tokenizer: Tokenizer, llmModel: LLMModel, filename: String, metadata: [String: Any], isEmbedded: Bool = false) {
        self.embeddingModel = embeddingModel
        self.tokenizer = tokenizer
        self.llmModel = llmModel
        self.filename = filename
        self.metadata = metadata
        self.isEmbedded = isEmbedded
    }
    
    /**
        * Exports the given chunks to an LLMRagFile.
        * - Parameter chunks: An array of Chunk objects to be exported.
        * - Returns: An LLMRagFile containing the exported chunks and metadata.
        * - Note: This method should handle the serialization of chunks and metadata into the LLMRagFile format.
        * - Throws: An error if the export fails.
        * Example usage:
        * ```swift
        * let exporter = ChunkExporter(embeddingModel: embeddingModel, tokenizer: tokenizer, ll
        * llmModel: llmModel, filename: "exported_chunks.llmrag", metadata: ["author": "NoesisNoema"])
        * let exportedFile = exporter.export(chunks: chunks)
        * ```
     */
    func export(chunks: [Chunk]) -> LLMRagFile {
        // TODO: implement
    }
    
    
}
