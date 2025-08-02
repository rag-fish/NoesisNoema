//// Created by [Your Name] on [Date].
///// License: MIT License
import Foundation

class ModelManager {

    /// The currently selected embedding model.
    var currentEmbeddingModel: EmbeddingModel
    /// The currently selected LLM model.
    var currentLLMModel: LLMModel

    /// The list of available embedding model names.
    /// Intended for use in UI dropdowns for embedding model selection in ContentView.
    let availableEmbeddingModels: [String] = [
        "default-embedding",
        "all-MiniLM-L6-v2",
        "LaBSE",
        "sentence-bert-base-ja"
    ]

    /// The list of available LLM model names.
    /// Intended for use in UI dropdowns for LLM model selection in ContentView.
    let availableLLMModels: [String] = [
        "default-llm",
        "llama3-8b",
        "llama3-70b",
        "gpt4all",
        "openchat",
        "mistral-7b",
        "phi-2",
        "tinyllama"
    ]

    /// Initializes a ModelManager with default models.
    init() {
        // Create default embedding model
        self.currentEmbeddingModel = EmbeddingModel(name: "default-embedding")
        // Create default LLM model
        self.currentLLMModel = LLMModel(name: "default-llm", modelFile: "", version: "")
    }

    /// Switches the current embedding model to the specified name, if available.
    /// - Parameter name: The name of the embedding model to switch to.
    func switchEmbeddingModel(name: String) {
        // If the requested model name exists in the available embedding models, switch to it.
        if availableEmbeddingModels.contains(name) {
            self.currentEmbeddingModel = EmbeddingModel(name: name)
        }
        // Optionally, else: ignore or handle error (not found)
    }

    /// Switches the current LLM model to the specified name, if available.
    /// - Parameter name: The name of the LLM model to switch to.
    func switchLLMModel(name: String) {
        var modelFile = ""
        var version = ""
        switch name {
        case "Llama-3":
            modelFile = "Resources/Models/llama3-8b.gguf"
            version = "8B"
        case "Phi-3-mini":
            modelFile = "Resources/Models/phi-3-mini.gguf"
            version = "mini"
        case "Gemma-2B":
            modelFile = "Resources/Models/gemma-2b.gguf"
            version = "2B"
        default:
            modelFile = ""
            version = ""
        }
        if availableLLMModels.contains(name) {
            self.currentLLMModel = LLMModel(name: name, modelFile: modelFile, version: version)
        }
        // Optionally, else: ignore or handle error (not found)
    }

    /// Stub for importing a new model resource.
    /// - Parameter file: The file to import (type depends on UI implementation).
    /// This method should handle loading a new model file (embedding or LLM), register it,
    /// and update the available model lists for UI selection. The implementation should
    /// handle validation, file storage, and updating `availableEmbeddingModels` or `availableLLMModels`.
    func importModelResource(file: Any) {
        // TODO: Implement model file import, registration, and update model lists.
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

    /// Generates an answer to a question using the LLM model (asynchronous)
    func generateAsyncAnswer(question: String) async -> String {
        // Wrap LLMModel's generate in async
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let result = self.currentLLMModel.generate(prompt: question)
                continuation.resume(returning: result)
            }
        }
    }

    /// Loads a model from a file.
    /// - Parameter file: The file to load the model from.
    /// This method should be implemented to handle different model types.
    func loadModel(from file: Any) {
        // TODO: Implement if needed.
    }

    static let shared = ModelManager()
} // Example usage of the ModelManager
