//// Created by NoesisNoema on 2024/02/24.
///// License: MIT License

import Foundation

class LLMRagFile {

    var filename: String
    var metadata: [String: Any]
    var chunks: [Chunk]
    var isEmbedded: Bool

    /// Initializes an LLMRagFile with a filename, metadata, and chunks.
    /// - Parameters:
    ///  - filename: The name of the file.
    ///  - metadata: A map containing metadata about the file.
    ///  - chunks: An array of Chunk objects representing the data.
    ///  - isEmbedded: A boolean indicating if the file is embedded.
    ///
    init(filename: String, metadata: [String: Any], chunks: [Chunk], isEmbedded: Bool = false) {
        self.filename = filename
        self.metadata = metadata
        self.chunks = chunks
        self.isEmbedded = isEmbedded
    }

}
