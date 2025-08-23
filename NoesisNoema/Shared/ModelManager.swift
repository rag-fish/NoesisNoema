//// Created by [Your Name] on [Date].
///// License: MIT License
import Foundation

class ModelManager {

    /// The currently selected embedding model.
    var currentEmbeddingModel: EmbeddingModel
    /// The currently selected LLM model.
    var currentLLMModel: LLMModel
    /// The current model specification from the registry
    private(set) var currentModelSpec: ModelSpec?

    /// LLM generation preset (auto or specific). Exposed to UI.
    private(set) var currentLLMPreset: String = "auto" // auto|factual|balanced|creative|json|code

    /// Cached LLM model names/ids for synchronous UI access
    private var cachedLLMModelNames: [String] = [
        "Jan-V1-4B",
        "Llama-3",
        "Phi-3-mini",
        "Gemma-2B",
        "GPT-OSS-20B"
    ]
    private var cachedLLMModelIds: [String] = [
        "jan-v1-4b",
        "llama-3-8b",
        "phi-3-mini",
        "gemma-2b",
        "gpt-oss-20b"
    ]

    /// The list of available embedding model names.
    /// Intended for use in UI dropdowns for embedding model selection in ContentView.
    let availableEmbeddingModels: [String] = [
        "default-embedding",
        "all-MiniLM-L6-v2",
        "LaBSE",
        "sentence-bert-base-ja"
    ]

    /// The list of available LLM presets for UI selection.
    let availableLLMPresets: [String] = ["auto", "factual", "balanced", "creative", "json", "code"]

    /// Initializes a ModelManager with default models.
    init() {
        // Create default embedding model
        self.currentEmbeddingModel = EmbeddingModel(name: "default-embedding")
        // Default LLM -> Jan-V1-4B (bundled under Resources/Models)
        self.currentLLMModel = LLMModel(name: "Jan-V1-4B", modelFile: "Jan-v1-4B-Q4_K_M.gguf", version: "4B")
        
        // Initialize model registry in background
        Task {
            await self.initializeModelRegistry()
        }
    }
    
    /// Get available LLM model names (synchronous snapshot for UI)
    var availableLLMModels: [String] {
        return cachedLLMModelNames
    }
    
    /// Get available LLM model IDs (synchronous snapshot for UI)
    var availableLLMModelIds: [String] {
        return cachedLLMModelIds
    }
    
    /// Initialize the model registry
    private func initializeModelRegistry() async {
        await ModelRegistry.shared.scanForModels()
        await ModelRegistry.shared.updateModelAvailability()
        
        // Try to set current model spec based on current LLM model
        let preferred = await ModelRegistry.shared.getModelSpec(id: "jan-v1-4b")
        if let preferred {
            self.currentModelSpec = preferred
        } else {
            let allSpecs = await ModelRegistry.shared.getAllModelSpecs()
            if let first = allSpecs.first { self.currentModelSpec = first }
        }
        
        // Update cached model lists for UI
        await self.updateCachedRegistrySnapshot()
    }

    /// Update cached LLM model lists from registry (available only)
    private func updateCachedRegistrySnapshot() async {
        let specs = await ModelRegistry.shared.getAvailableModelSpecs()
        self.cachedLLMModelNames = specs.map { $0.name }
        self.cachedLLMModelIds = specs.map { $0.id }
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

    /// Switches the current LLM model to the specified name or ID, if available.
    /// - Parameter identifier: The name or ID of the LLM model to switch to.
    func switchLLMModel(identifier: String) {
        Task {
            await self.switchLLMModelAsync(identifier: identifier)
        }
    }

    /// Backward-compatible wrapper for callers using the old external label 'name'.
    func switchLLMModel(name: String) {
        switchLLMModel(identifier: name)
    }
    
    /// Async version of switchLLMModel that uses the model registry
    func switchLLMModelAsync(identifier: String) async {
        // First try to find by ID
        var spec = await ModelRegistry.shared.getModelSpec(id: identifier.lowercased())
        
        // If not found by ID, try to find by name
        if spec == nil {
            let allSpecs = await ModelRegistry.shared.getAllModelSpecs()
            spec = allSpecs.first { $0.name.lowercased() == identifier.lowercased() }
        }
        
        // Fallback to legacy mapping for backward compatibility
        if spec == nil {
            spec = await getLegacyModelSpec(name: identifier)
        }
        
        guard let modelSpec = spec else {
            print("[ModelManager] Model not found: \(identifier)")
            return
        }
        
        // Update current model and spec
        self.currentLLMModel = LLMModel(
            name: modelSpec.name,
            modelFile: modelSpec.modelFile,
            version: modelSpec.version
        )
        self.currentModelSpec = modelSpec
        
        print("[ModelManager] Switched to model: \(modelSpec.name) (\(modelSpec.id))")
    }
    
    /// Legacy model mapping for backward compatibility
    private func getLegacyModelSpec(name: String) async -> ModelSpec? {
        switch name {
        case "Jan-V1-4B":
            return await ModelRegistry.shared.getModelSpec(id: "jan-v1-4b")
        case "Llama-3":
            return await ModelRegistry.shared.getModelSpec(id: "llama-3-8b")
        case "Phi-3-mini":
            return await ModelRegistry.shared.getModelSpec(id: "phi-3-mini")
        case "Gemma-2B":
            return await ModelRegistry.shared.getModelSpec(id: "gemma-2b")
        case "GPT-OSS-20B":
            return await ModelRegistry.shared.getModelSpec(id: "gpt-oss-20b")
        default:
            return nil
        }
    }

    /// Set the current LLM preset (UI-driven). Unknown values fallback to 'auto'.
    func setLLMPreset(name: String) {
        if availableLLMPresets.contains(name.lowercased()) {
            self.currentLLMPreset = name.lowercased()
        } else {
            self.currentLLMPreset = "auto"
        }
    }

    /// Get the current model's runtime parameters
    func getCurrentRuntimeParams() -> RuntimeParams? {
        return currentModelSpec?.runtimeParams
    }
    
    /// Get OOM-safe runtime parameters for the current model
    func getOOMSafeParams() -> RuntimeParams {
        return currentModelSpec?.runtimeParams ?? RuntimeParams.oomSafeDefaults()
    }
    
    /// Refresh model registry and update availability
    func refreshModelRegistry() async {
        await ModelRegistry.shared.scanForModels()
        await ModelRegistry.shared.updateModelAvailability()
        
        // Update current model spec if it exists
        if let currentSpec = currentModelSpec {
            if let updatedSpec = await ModelRegistry.shared.getModelSpec(id: currentSpec.id) {
                self.currentModelSpec = updatedSpec
            }
        }
        
        // Update cached lists
        await self.updateCachedRegistrySnapshot()
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
} // Example usage of the ModelManagerっこう
