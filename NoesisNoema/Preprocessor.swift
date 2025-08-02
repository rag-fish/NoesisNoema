import Foundation

class Preprocessor {
    var embeddingModel: EmbeddingModel
    
    @discardableResult
    init(embeddingModel: EmbeddingModel) {
        self.embeddingModel = embeddingModel
    }
    
    func preprocess(document: Any) -> [Chunk] {
        let text: String
        if let str = document as? String {
            text = str
        } else {
            text = String(describing: document)
        }
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var chunks: [Chunk] = []
        for sentence in sentences {
            let embedding = embeddingModel.embed(text: sentence)
            chunks.append(Chunk(content: sentence, embedding: embedding))
        }
        return chunks
    }
    
    func exportRAGpack(chunks: [Chunk], to url: URL) {
        // TODO: RAGpack serialization is currently handled by CLI/Colab tools.
        // This method is a stub for possible future in-app export functionality.
        // 例: JSON+NumPy形式でchunks/embeddings/metadataをzip化
        print("[Preprocessor] exportRAGpack is not implemented yet.")
    }
    
}
