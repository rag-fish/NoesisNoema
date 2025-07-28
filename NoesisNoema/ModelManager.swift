//// Created by [Your Name] on [Date].
///// License: MIT License
import Foundation

class ModelManager {
    
    /// Initializes a ModelManager with default models.
    var currentEmbeddingModel: EmbeddingModel
    var currentLLMModel: LLMModel
    
    init() {
        // デフォルトのTokenizerを生成（引数なし or 必要ならデフォルト値を指定）
        let defaultTokenizer = Tokenizer()
        // デフォルトのEmbeddingModelを生成
        self.currentEmbeddingModel = EmbeddingModel(name: "default-embedding", tokenizer: defaultTokenizer)
        // デフォルトのLLMModelを生成（Tokenizer必須）
        self.currentLLMModel = LLMModel(name: "default-llm", modelFile: "", version: "", tokenizer: defaultTokenizer)
    }
    
    /// Adds a new embedding model to the manager.
    func switchEmbeddingModel(name: Any) -> Void {
        // TODO: implement
    }
    
    /// Adds a new LLM model to the manager.
    func switchLLMModel(name: Any) -> Void {
        // TODO: implement
    }
    
    /// Generates an embedding for the given text using the current embedding model.
    /// - Parameter text: The text to embed.
    /// - Returns: An array of floats representing the embedding.
    func generateEmbedding(for text: String) -> [Float] {
        return currentEmbeddingModel.embed(text: text)
    }
    
    /// Generates a response from the current LLM model based on the provided prompt.
    /// - Parameter prompt: The prompt to generate a response for.
    /// - Returns: A string containing the generated response.
    func generateResponse(for prompt: String) -> String {
        return currentLLMModel.generate(prompt: prompt)
    }
    
    /// Loads a model from a file.
    /// - Parameter file: The file to load the model from.
    /// /// This method should be implemented to handle different model types.
    func loadModel(from file: Any) {
        
        
    }
    
}// Example usage of the ModelManager
