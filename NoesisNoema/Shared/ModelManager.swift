//// Created by [Your Name] on [Date].
///// License: MIT License
import Foundation

class ModelManager {

    /// The currently selected embedding model.
    var currentEmbeddingModel: EmbeddingModel
    /// The currently selected LLM model.
    var currentLLMModel: LLMModel

    /// LLM generation preset (auto or specific). Exposed to UI.
    private(set) var currentLLMPreset: String = "auto" // auto|factual|balanced|creative|json|code

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
        // Align with UI picker options and include Jan-V1-4B
        "Jan-V1-4B",
        "Llama-3",
        "Phi-3-mini",
        "Gemma-2B",
        // Add new OSS GPT model
        "GPT-OSS-20B",
        // legacy/other options can remain available if needed
        "default-llm",
        "llama3-8b",
        "llama3-70b",
        "gpt4all",
        "openchat",
        "mistral-7b",
        "phi-2",
        "tinyllama"
    ]

    /// The list of available LLM presets for UI selection.
    let availableLLMPresets: [String] = ["auto", "factual", "balanced", "creative", "json", "code"]

    /// Initializes a ModelManager with default models.
    init() {
        // Create default embedding model
        self.currentEmbeddingModel = EmbeddingModel(name: "default-embedding")
        // Default LLM -> Jan-V1-4B (bundled under Resources/Models)
        self.currentLLMModel = LLMModel(name: "Jan-V1-4B", modelFile: "Jan-v1-4B-Q4_K_M.gguf", version: "4B")
    }

    /// Switches the current embedding model to the specified name, if available.
    /// - Parameter name: The name of the embedding model to switch to.
    func switchEmbeddingModel(name: String) {
        if availableEmbeddingModels.contains(name) {
            self.currentEmbeddingModel = EmbeddingModel(name: name)
            // VectorStore の検索用モデルも同期
            VectorStore.shared.embeddingModel = self.currentEmbeddingModel
        }
    }

    /// Switches the current LLM model to the specified name, if available.
    /// - Parameter name: The name of the LLM model to switch to.
    func switchLLMModel(name: String) {
        var modelFile = ""
        var version = ""
        switch name {
        case "Jan-V1-4B":
            modelFile = "Jan-v1-4B-Q4_K_M.gguf"
            version = "4B"
        case "Llama-3":
            modelFile = "llama3-8b.gguf"
            version = "8B"
        case "Phi-3-mini":
            modelFile = "phi-3-mini.gguf"
            version = "mini"
        case "Gemma-2B":
            modelFile = "gemma-2b.gguf"
            version = "2B"
        case "GPT-OSS-20B":
            modelFile = "gpt-oss-20b-Q4_K_S.gguf"
            version = "20B"
        default:
            modelFile = ""
            version = ""
        }
        if availableLLMModels.contains(name) {
            self.currentLLMModel = LLMModel(name: name, modelFile: modelFile, version: version)
        }
        // Optionally, else: ignore or handle error (not found)
    }

    /// Set the current LLM preset (UI-driven). Unknown values fallback to 'auto'.
    func setLLMPreset(name: String) {
        if availableLLMPresets.contains(name.lowercased()) {
            self.currentLLMPreset = name.lowercased()
        } else {
            self.currentLLMPreset = "auto"
        }
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
        // RAG文脈を構築
        let embedding = self.currentEmbeddingModel.embed(text: question)
        let topChunks = VectorStore.shared.findRelevant(queryEmbedding: embedding, topK: 6)
        var context = topChunks.map { $0.content }.joined(separator: "\n---\n")
        if context.isEmpty { context = "" }
        // コンテキストの安全上限（簡易）
        if context.count > 2000 { context = String(context.prefix(2000)) }

        // @Sendable 回避: モデルをローカルへ
        let model = self.currentLLMModel
        let ctx = context.isEmpty ? nil : context
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let result = model.generate(prompt: question, context: ctx)
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
