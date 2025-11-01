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

    // MARK: - UI-facing additions
    @Published private(set) var currentEmbeddingModel: EmbeddingModel = EmbeddingModel(name: "nomic-embed-text")
    @Published private(set) var currentLLMModel: LLMModel = LLMModel(name: "Jan-V1-4B", modelFile: "Jan-v1-4B-Q4_K_M.gguf", version: "v1", isEmbedded: true)
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
        }
    }

    /// Resources/ModelsディレクトリとRegistryをスキャン
    func scanAvailableModels() async {
        await registry.scanForModels()
        availableModels = await registry.getAvailableModelSpecs()
        SystemLog().logEvent(event: "[ModelManager] Found \(availableModels.count) models")
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
            currentLLMModel = LLMModel(name: spec.name, modelFile: spec.modelFile, version: spec.version, isEmbedded: true)
        } else {
            currentLLMModel = LLMModel(name: name, modelFile: "", version: "v1", isEmbedded: true)
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

    /// Minimal stub that produces a quick answer and records no sources
    func generateAsyncAnswer(question: String) async -> String {
        // In a real implementation, this would run RAG + inference. Keep it simple to unblock UI.
        let prefix = currentLLMModel.name
        return "[\(prefix)] \(question)"
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
