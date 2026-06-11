// filepath: NoesisNoema/Shared/ModelManager.swift
// Project: NoesisNoema
// Description: Dynamic model management - multi-GGUF model loading/switching/inference
// License: MIT License

import Foundation

// Expose runtime mode globally for UI usage
enum LLMRuntimeMode { case auto, cpuOnly }

/// 動的モデル管理 - 複数GGUFモデルのロード/切り替え/推論を統括
@MainActor
class ModelManager: ObservableObject {
    static let shared = ModelManager()

    @Published var loadedModels: [String: any InferenceEngine] = [:]
    @Published var currentModelID: String?
    @Published var availableModels: [ModelSpec] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isGenerating = false  // Guard against double-submit
    @Published var selectedModelID: ModelID?  // Strongly-typed model selection

    // MARK: - UI-facing additions
    @Published private(set) var currentEmbeddingModel: EmbeddingModel = EmbeddingModel(name: "nomic-embed-text")
    @Published private(set) var currentLLMModel: LLMModel = LLMModel(name: "Llama 3.2 3B", modelFile: "Llama-3.2-3B-Instruct-Q4_K_M.gguf", version: "3.2", isEmbedded: true)
    @Published private(set) var currentLLMPreset: String = "auto"

    // Hardware-level runtime mode (macOS UI)
    @Published private(set) var llmRuntimeMode: LLMRuntimeMode = .auto

    // Parameter-level runtime mode (iOS UI)
    @Published private(set) var paramRuntimeMode: RuntimeMode = .recommended

    // Simple memory of last retrieved chunks for citation UI
    @Published private(set) var lastRetrievedChunks: [Chunk] = []

    let registry = ModelRegistry.shared
    private let hwProfile = HardwareProbe.probe()

    init() {
        Task {
            await scanAvailableModels()
            await setDefaultModel()
        }
    }

    /// Resources/ModelsディレクトリとRegistryをスキャン
    func scanAvailableModels() async {
        await registry.scanForModels()
        availableModels = await registry.getAvailableModelSpecs()
        SystemLog().logEvent(event: "[ModelManager] Found \(availableModels.count) models")
    }

    /// Set default model after registry completes
    private func setDefaultModel() async {
        guard !availableModels.isEmpty else { return }

        // Try to restore last selection from UserDefaults
        // SAFE: Small string ID (< 100 bytes)
        if let lastModelIDString = UserDefaults.standard.string(forKey: "lastSelectedModelID"),
           !availableModels.contains(where: { $0.id == lastModelIDString }) {
            // Saved ID is stale — e.g. the embedder GGUF that Layer 1 now excludes
            // from availableModels. Clear it so the warning does not re-fire on every
            // launch, then fall through to the configured-default path below.
            UserDefaults.standard.removeObject(forKey: "lastSelectedModelID")
            SystemLog().logEvent(event: "[ModelManager] Cleared stale lastSelectedModelID: \(lastModelIDString)")
        }

        if let lastModelIDString = UserDefaults.standard.string(forKey: "lastSelectedModelID"),
           availableModels.contains(where: { $0.id == lastModelIDString }) {
            selectedModelID = ModelID(lastModelIDString)
            currentModelID = lastModelIDString
            if let spec = availableModels.first(where: { $0.id == lastModelIDString }) {
                currentLLMModel = LLMModel(name: spec.name, modelFile: spec.modelFile, version: spec.version, isEmbedded: true)
            }
            SystemLog().logEvent(event: "[ModelManager] Restored last model: \(lastModelIDString)")
        } else {
            // Prefer the configured default model — the one currentLLMModel is
            // declared with — when its file is among the available models;
            // otherwise fall back to the first available model. Matching on
            // modelFile (not name) keeps the declared default authoritative
            // even when several models are bundled.
            let configuredFile = currentLLMModel.modelFile
            let defaultModel = availableModels.first(where: { $0.modelFile == configuredFile })
                ?? availableModels.first
            if let defaultModel {
                selectedModelID = ModelID(defaultModel.id)
                currentModelID = defaultModel.id
                currentLLMModel = LLMModel(name: defaultModel.name, modelFile: defaultModel.modelFile, version: defaultModel.version, isEmbedded: true)
                SystemLog().logEvent(event: "[ModelManager] Set default model: \(defaultModel.name)")
            }
        }
    }

    /// モデルをロード（既にロード済みならスキップ）
    func loadModel(id: String) async throws {
        guard loadedModels[id] == nil else {
            currentModelID = id
            SystemLog().logEvent(event: "[ModelManager] Model already loaded: \(id)")
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let spec = await registry.getModelSpec(id: id) else {
            let error = InferenceError.modelNotLoaded
            errorMessage = error.localizedDescription
            throw error
        }

        // ハードウェアプロファイルに基づいてランタイムパラメータを自動調整
        let autoParams = await autotuneParams(for: spec.metadata)

        // モデルファイルパスを解決
        guard let modelPath = resolveModelPath(fileName: spec.modelFile) else {
            let error = InferenceError.modelNotLoaded
            errorMessage = "Model file not found: \(spec.modelFile)"
            SystemLog().logEvent(event: "[ModelManager] \(errorMessage ?? "")")
            throw error
        }

        // Use ModelFactory to create appropriate engine
        do {
            let engine = try await ModelFactory.createEngine(
                modelPath: modelPath,
                metadata: spec.metadata,
                runtimeParams: autoParams
            )
            loadedModels[id] = engine
        } catch {
            errorMessage = "Failed to initialize engine: \(error.localizedDescription)"
            SystemLog().logEvent(event: "[ModelManager] \(errorMessage ?? "")")
            throw error
        }
        currentModelID = id

        SystemLog().logEvent(event: "[ModelManager] Loaded model: \(spec.name) (\(spec.metadata.architecture), \(spec.metadata.parameterCount)B params)")
    }

    /// 現在のモデルを取得
    func getCurrentEngine() -> (any InferenceEngine)? {
        guard let id = currentModelID else { return nil }
        return loadedModels[id]
    }

    /// モデルをアンロード（メモリ解放）
    func unloadModel(id: String) {
        loadedModels.removeValue(forKey: id)
        SystemLog().logEvent(event: "[ModelManager] Unloaded model: \(id)")

        if currentModelID == id {
            currentModelID = availableModels.first?.id
        }
    }

    /// 全モデルをアンロード
    func unloadAllModels() {
        loadedModels.removeAll()
        currentModelID = nil
        SystemLog().logEvent(event: "[ModelManager] Unloaded all models")
    }

    /// ハードウェアプロファイルに基づく自動チューニング
    private func autotuneParams(for metadata: GGUFMetadata) async -> RuntimeParams {
        var params = RuntimeParams.oomSafeDefaults()

        // コンテキスト長をモデルの能力に合わせて調整
        params.nCtx = min(params.nCtx, metadata.contextLength)

        // 大規模モデル（20B+）の場合はより保守的に
        if metadata.parameterCount >= 20.0 {
            params.nCtx = min(params.nCtx, 2048)
            params.nBatch = min(params.nBatch, 256)
            #if os(iOS)
            params.nGpuLayers = 0 // iOS: CPU強制
            #else
            params.nGpuLayers = 0 // macOSでも大規模モデルはCPU
            #endif
        } else if metadata.parameterCount >= 8.0 {
            // 中規模モデル（8B-20B）
            #if os(iOS)
            params.nGpuLayers = 0
            params.nCtx = min(params.nCtx, 2048)
            #else
            params.nGpuLayers = 32 // 部分的GPU利用
            #endif
        } else {
            // 小規模モデル（8B未満）
            #if os(iOS)
            params.nGpuLayers = 0
            #else
            params.nGpuLayers = 999 // GPU最大活用
            #endif
        }

        // Flash Attention対応モデルは有効化
        params.useFlashAttention = metadata.supportsFlashAttention

        SystemLog().logEvent(event: "[ModelManager] Autotuned: nCtx=\(params.nCtx), nBatch=\(params.nBatch), GPU=\(params.nGpuLayers), FA=\(params.useFlashAttention)")

        return params
    }

    /// モデルファイルパスの解決
    private func resolveModelPath(fileName: String) -> String? {
        let searchPaths = [
            "Resources/Models",
            "Models",
            ""
        ]

        for subdir in searchPaths {
            if let url = Bundle.main.url(forResource: (fileName as NSString).deletingPathExtension,
                                        withExtension: (fileName as NSString).pathExtension,
                                        subdirectory: subdir.isEmpty ? nil : subdir) {
                return url.path
            }
        }

        return nil
    }

    // MARK: - UI-facing additions

    var availableEmbeddingModels: [String] { ["nomic-embed-text"] }
    var availableLLMModels: [String] { availableModels.map { $0.name } }
    var availableLLMPresets: [String] { ["auto", "balanced", "creative", "precise"] }

    func switchEmbeddingModel(name: String) {
        currentEmbeddingModel = EmbeddingModel(name: name)
    }

    func switchLLMModel(name: String) {
        // Update current model selection; attempt to point to registry spec if present
        if let spec = availableModels.first(where: { $0.name == name }) {
            currentModelID = spec.id
            selectedModelID = ModelID(spec.id)
            currentLLMModel = LLMModel(name: spec.name, modelFile: spec.modelFile, version: spec.version, isEmbedded: true)
            // Persist selection
            UserDefaults.standard.set(spec.id, forKey: "lastSelectedModelID")
        } else {
            currentLLMModel = LLMModel(name: name, modelFile: "", version: "v1", isEmbedded: true)
        }
    }

    func switchLLMModelByID(_ modelID: ModelID) {
        if let spec = availableModels.first(where: { $0.id == modelID.rawValue }) {
            currentModelID = spec.id
            selectedModelID = modelID
            currentLLMModel = LLMModel(name: spec.name, modelFile: spec.modelFile, version: spec.version, isEmbedded: true)
            // Persist selection (SAFE: Small string ID)
            UserDefaults.standard.set(spec.id, forKey: "lastSelectedModelID")
        }
    }

    func setLLMPreset(name: String) { currentLLMPreset = name }

    // macOS API: hardware runtime mode
    func getLLMRuntimeMode() -> LLMRuntimeMode { llmRuntimeMode }
    func setLLMRuntimeMode(_ mode: LLMRuntimeMode) { llmRuntimeMode = mode }

    // iOS API: parameter runtime mode
    func getRuntimeMode() -> RuntimeMode { paramRuntimeMode }
    func setRuntimeMode(_ mode: RuntimeMode) { paramRuntimeMode = mode }

    func resetToRecommended() {
        llmRuntimeMode = .auto
        paramRuntimeMode = .recommended
        currentLLMPreset = "auto"
    }

    func isFullyLocal() -> Bool { true }

    /// Full RAG implementation: retrieves chunks and generates answer with citations
    /// PERFORMANCE: Moved off @MainActor - runs entirely on background thread
    nonisolated func generateAsyncAnswer(question: String) async -> String {
        // Measure total time
        let perfStart = Date()

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🎬 [ModelManager] generateAsyncAnswer CALLED")
        print("   Question: \(question.prefix(50))...")

        let currentModel = await MainActor.run { self.currentLLMModel }
        print("   Current LLM: \(currentModel.name)")
        print("   Model file: \(currentModel.modelFile)")

        // Set generating state on MainActor
        await MainActor.run { self.isGenerating = true }
        print("🔒 [ModelManager] Set isGenerating = true")

        defer {
            Task { @MainActor in
                self.isGenerating = false
            }
            print("🔓 [ModelManager] Will set isGenerating = false in defer")
        }

        let _log = SystemLog()
        _log.logEvent(event: "[ModelManager] generateAsyncAnswer enter qLen=\(question.count)")
        #if DEBUG
        print("🚀 [ModelManager] Starting generation for question: \(question.prefix(50))...")
        #endif

        defer {
            let dt = Date().timeIntervalSince(perfStart)
            _log.logEvent(event: String(format: "[ModelManager] generateAsyncAnswer exit (%.2f ms)", dt*1000))
            #if DEBUG
            print("✅ [ModelManager] Generation completed in \(String(format: "%.2f", dt*1000))ms")
            #endif
        }

        // PERFORMANCE: Stage 1 - Retrieve relevant chunks (off main thread)
        let retrieveStart = Date()
        _log.logEvent(event: "[ModelManager] Retrieving RAG context...")
        print("[RAG] chunks loaded:", VectorStore.shared.chunks.count)
        print("[RAG] query =", question)

        #if DEBUG
        print("📚 [ModelManager] Retrieving RAG context...")
        #endif

        // Run retrieval in background
        let chunks = await Task.detached(priority: .userInitiated) {
            let retriever = LocalRetriever(store: VectorStore.shared)
            #if os(iOS)
            return retriever.retrieve(query: question, k: 3, trace: false)
            #else
            return retriever.retrieve(query: question, k: 5, trace: false)
            #endif
        }.value

        let retrieveTime = Date().timeIntervalSince(retrieveStart)
        _log.logEvent(event: String(format: "[PERF] Retrieval: %.2f ms", retrieveTime*1000))

        #if DEBUG
        print("📚 [ModelManager] Retrieved \(chunks.count) chunks in \(String(format: "%.2f", retrieveTime*1000))ms")
        if !chunks.isEmpty {
            print("📚 [ModelManager] Context preview: \(chunks.map { $0.content.prefix(50) })")
        }
        #endif

        // Store chunks for citation UI (MainActor)
        await MainActor.run {
            self.lastRetrievedChunks = chunks
        }

        // PERFORMANCE: Stage 2 - Build context (off main thread)
        let contextStart = Date()
        let context = chunks.map { $0.content }.joined(separator: "\n\n")
        let contextTime = Date().timeIntervalSince(contextStart)

        _log.logEvent(event: String(format: "[PERF] Context build: %.2f ms, length: %d chars", contextTime*1000, context.count))
        #if DEBUG
        print("📝 [ModelManager] Built context with \(context.count) characters in \(String(format: "%.2f", contextTime*1000))ms")
        if context.isEmpty {
            print("⚠️ [ModelManager] WARNING: Context is EMPTY - RAG will not work!")
            print("   VectorStore has \(VectorStore.shared.chunks.count) chunks")
        } else {
            print("📝 [ModelManager] Context preview: \(context.prefix(200))...")
        }
        #endif

        // PERFORMANCE: Stage 3 - Generate answer using LLM (off main thread)
        let genStart = Date()
        _log.logEvent(event: "[ModelManager] Calling LLM generateAsync...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🚀 [ModelManager] About to call currentLLMModel.generateAsync()")
        #if DEBUG
        print("🧠 [ModelManager] Calling LLM model: \(currentModel.name)")
        print("🧠 [ModelManager] Model file: \(currentModel.modelFile)")
        print("🧠 [ModelManager] Prompt: \(question.prefix(80))...")
        print("🧠 [ModelManager] Context: \(context.isEmpty ? "none" : "\(context.count) chars")")
        #endif

        // Belt-and-braces (Layer 3): even after the registry-scan exclusion (Layer 1)
        // and the stale-UserDefaults cleanup (Layer 2), warn if the model we are about
        // to drive looks like an embedder — catches future surprise paths (e.g. a direct
        // switchLLMModel("nomic-embed-text-…") call) without altering control flow.
        if currentModel.modelFile.lowercased().contains("embed") {
            _log.logEvent(event: "[ModelManager] WARN: currentLLMModel.modelFile looks like an embedder: \(currentModel.modelFile)")
        }

        let answer: String
        do {
            print("🎯 [ModelManager] Calling generateAsync NOW...")
            answer = try await currentModel.generateAsync(prompt: question, context: context.isEmpty ? nil : context)
            let genTime = Date().timeIntervalSince(genStart)
            _log.logEvent(event: String(format: "[PERF] Generation: %.2f ms", genTime*1000))
            print("✅ [ModelManager] generateAsync returned: \(answer.count) chars in \(String(format: "%.2f", genTime*1000))ms")
            #if DEBUG
            if answer.isEmpty {
                print("❌ [ModelManager] ERROR: LLM returned EMPTY answer!")
            }
            #endif
        } catch {
            let errorMsg = "LLM generation failed: \(error.localizedDescription)"
            _log.logEvent(event: "[ModelManager] ERROR: \(errorMsg)")
            #if DEBUG
            print("❌ [ModelManager] \(errorMsg)")
            #endif
            return errorMsg
        }

        if answer.isEmpty {
            print("[RAG] WARNING: Empty response generated")
            return "No response generated. Please try again."
        }

        #if DEBUG
        print("💬 [ModelManager] LLM response length: \(answer.count) chars")
        print("💬 [ModelManager] Response preview: \(answer.prefix(100))")
        #endif
        _log.logEvent(event: "[ModelManager] LLM response length: \(answer.count)")

        return answer
    }

    /// Fire-and-forget autotune stub; calls completion with optional warning string
    func autotuneCurrentModelAsync(trace: Bool, timeoutSeconds: Double, completion: @escaping (String) -> Void) {
        Task { @MainActor in
            // Simulate quick tuning and optional warning
            try? await Task.sleep(nanoseconds: UInt64(0.2 * 1_000_000_000))
            completion("")
        }
    }
}
