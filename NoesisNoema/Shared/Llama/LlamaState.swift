import Foundation

#if BRIDGE_TEST
// Minimal ModelManager stub for CLI builds if not included in target
@MainActor
class _CLI_ModelManager {
    static let shared = _CLI_ModelManager()
    private var mockEngine: _MockInferenceEngine? = nil

    func loadModel(id: String) async throws {
        mockEngine = _MockInferenceEngine()
    }

    func getCurrentEngine() -> _MockInferenceEngine? {
        return mockEngine
    }
}

// Minimal InferenceEngine stub for CLI
actor _MockInferenceEngine {
    func generate(prompt: String, maxTokens: Int32) async throws -> String {
        return "[BRIDGE_TEST stub response]"
    }
}

typealias ModelManager = _CLI_ModelManager
#endif

struct Model: Identifiable {
    var id = UUID()
    var name: String
    var url: String
    var filename: String
    var status: String?
}

@MainActor
class LlamaState: ObservableObject {
    @Published var messageLog = ""
    @Published var cacheCleared = false
    @Published var downloadedModels: [Model] = []
    @Published var undownloadedModels: [Model] = []
    let NS_PER_S = 1_000_000_000.0

    private var llamaContext: LlamaContext?
    private var defaultModelUrl: URL? {
        // プラットフォーム優先: iOSはJan、macOSはLlama3-8B
        #if os(macOS)
        let primaryFile = "llama3-8b.gguf"
        let secondaryFile = "Jan-v1-4B-Q4_K_M.gguf"
        #else
        let primaryFile = "Jan-v1-4B-Q4_K_M.gguf"
        let secondaryFile = "llama3-8b.gguf"
        #endif
        func findInBundle(_ file: String) -> URL? {
            let nameNoExt = (file as NSString).deletingPathExtension
            let ext = (file as NSString).pathExtension
            let subs = [nil, "Models", "Resources/Models", "Resources"]
            for sub in subs {
                if let url = Bundle.main.url(forResource: nameNoExt, withExtension: ext, subdirectory: sub) {
                    return url
                }
            }
            return nil
        }
        if let url = findInBundle(primaryFile) { return url }
        if let url = findInBundle(secondaryFile) { return url }
        // 旧フォールバック
        return Bundle.main.url(forResource: "ggml-model", withExtension: "gguf", subdirectory: "models")
    }

    struct SamplingConfig {
        var temp: Float
        var topK: Int32
        var topP: Float
        var seed: UInt64
        var nLen: Int32
    }
    enum Preset: String { case factual, balanced, creative, json, code }

    private var pendingConfig: SamplingConfig = SamplingConfig(temp: 0.5, topK: 60, topP: 0.9, seed: 1234, nLen: 512)

    // 新規: ModelManager統合（既存コードとの互換性を保持）
    private let modelManager = ModelManager.shared
    private var useModelManager = false // フラグで新旧API切り替え

    init() {
        // ランタイムガード（壊れたFWを早期検知）
        if let err = LlamaRuntimeCheck.ensureLoadable() {
            let msg = "[LlamaRuntimeCheck] \(err)"
            messageLog += msg + "\n"
            SystemLog().logEvent(event: msg)
        }
        loadModelsFromDisk()
        loadDefaultModels()
    }

    // 新規: ModelManager経由でモデルをロード
    func loadModelViaManager(id: String) async throws {
        try await modelManager.loadModel(id: id)
        useModelManager = true
        messageLog += "Loaded model via ModelManager: \(id)\n"
        SystemLog().logEvent(event: "[LlamaState] Using ModelManager for model: \(id)")
    }

    // 新規: ModelManager経由の推論
    func completeViaManager(text: String, maxTokens: Int32 = 512) async -> String {
        guard useModelManager else {
            return await complete(text: text) // フォールバック
        }

        guard let engine = modelManager.getCurrentEngine() else {
            messageLog += "ERROR: No model loaded in ModelManager\n"
            return ""
        }

        messageLog += "USER: \(text)\n"

        do {
            let result = try await engine.generate(prompt: text, maxTokens: maxTokens)
            let normalized = normalizeOutput(result)
            messageLog += "ASSISTANT: \(normalized)\n"
            return normalized
        } catch {
            let err = "Generation failed: \(error.localizedDescription)"
            messageLog += err + "\n"
            return ""
        }
    }

    // プリセット→SamplingConfig 変換
    private func config(for preset: Preset) -> SamplingConfig {
        switch preset {
        case .factual:
            return SamplingConfig(temp: 0.2, topK: 40, topP: 0.85, seed: 1234, nLen: 384)
        case .balanced:
            return SamplingConfig(temp: 0.5, topK: 60, topP: 0.9, seed: 1234, nLen: 512)
        case .creative:
            return SamplingConfig(temp: 0.9, topK: 100, topP: 0.95, seed: 1234, nLen: 768)
        case .json:
            return SamplingConfig(temp: 0.2, topK: 40, topP: 0.9, seed: 1234, nLen: 512)
        case .code:
            return SamplingConfig(temp: 0.3, topK: 50, topP: 0.9, seed: 1234, nLen: 640)
        }
    }

    // インテント検出（簡易）
    private func detectIntent(prompt: String) -> Preset {
        let p = prompt.lowercased()
        if p.contains("context:") || p.contains("reference:") || p.contains("資料:") { return .factual }
        if p.contains("json") || p.contains("return json") || p.contains("出力はjson") || p.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") { return .json }
        if p.contains("```") || p.contains("code") || p.contains("swift") || p.contains("python") || p.contains("関数") || p.contains("コード") { return .code }
        if p.contains("story") || p.contains("poem") || p.contains("creative") || p.contains("アイデア") { return .creative }
        return .balanced
    }

    // モデル名＋インテントで自動プリセット選択
    func autoSelectPreset(modelFileName: String, prompt: String) -> Preset {
        var intent = detectIntent(prompt: prompt)
        let fn = modelFileName.lowercased()
        if fn.contains("jan") || fn.contains("qwen") {
            if intent == .balanced { intent = .factual }
        } else if fn.contains("llama3") {
            if intent == .factual { intent = .balanced }
        } else if fn.contains("mistral") || fn.contains("phi") || fn.contains("tinyllama") {
            if intent == .creative { intent = .balanced }
        }
        return intent
    }

    // 設定の反映（LlamaContextへ）
    private func applyConfigToContext() async {
        guard let llamaContext else { return }
        await llamaContext.configure_sampling(temp: pendingConfig.temp, top_k: pendingConfig.topK, top_p: pendingConfig.topP, seed: pendingConfig.seed)
        await llamaContext.set_n_len(pendingConfig.nLen)
    }

    // 外部公開: プリセット適用
    func setPreset(_ name: String) async {
        if let p = Preset(rawValue: name) {
            pendingConfig = config(for: p)
            await applyConfigToContext()
        }
    }

    // 外部公開: 直接設定
    func configure(temp: Float? = nil, topK: Int32? = nil, topP: Float? = nil, seed: UInt64? = nil, nLen: Int32? = nil) async {
        pendingConfig = SamplingConfig(
            temp: temp ?? pendingConfig.temp,
            topK: topK ?? pendingConfig.topK,
            topP: topP ?? pendingConfig.topP,
            seed: seed ?? pendingConfig.seed,
            nLen: nLen ?? pendingConfig.nLen
        )
        await applyConfigToContext()
    }

    // 外部公開: verbose ブリッジ
    func setVerbose(_ on: Bool) async {
        guard let llamaContext else { return }
        await llamaContext.set_verbose(on)
    }

    private func loadModelsFromDisk() {
        do {
            let documentsURL = getDocumentsDirectory()
            let modelURLs = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
            for modelURL in modelURLs {
                let modelName = modelURL.deletingPathExtension().lastPathComponent
                downloadedModels.append(Model(name: modelName, url: "", filename: modelURL.lastPathComponent, status: "downloaded"))
            }
        } catch {
            print("Error loading models from disk: \(error)")
        }
    }

    private func loadDefaultModels() {
        do {
            try loadModel(modelUrl: defaultModelUrl)
        } catch {
            messageLog += "Error!\n"
        }

        for model in defaultModels {
            let fileURL = getDocumentsDirectory().appendingPathComponent(model.filename)
            if FileManager.default.fileExists(atPath: fileURL.path) {

            } else {
                var undownloadedModel = model
                undownloadedModel.status = "download"
                undownloadedModels.append(undownloadedModel)
            }
        }
    }

    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    private let defaultModels: [Model] = [
        Model(name: "TinyLlama-1.1B (Q4_0, 0.6 GiB)",url: "https://huggingface.co/TheBloke/TinyLlama-1.1B-1T-OpenOrca-GGUF/resolve/main/tinyllama-1.1b-1t-openorca.Q4_0.gguf?download=true",filename: "tinyllama-1.1b-1t-openorca.Q4_0.gguf", status: "download"),
        Model(
            name: "TinyLlama-1.1B Chat (Q8_0, 1.1 GiB)",
            url: "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q8_0.gguf?download=true",
            filename: "tinyllama-1.1b-chat-v1.0.Q8_0.gguf", status: "download"
        ),

        Model(
            name: "TinyLlama-1.1B (F16, 2.2 GiB)",
            url: "https://huggingface.co/ggml-org/models/resolve/main/tinyllama-1.1b/ggml-model-f16.gguf?download=true",
            filename: "tinyllama-1.1b-f16.gguf", status: "download"
        ),

        Model(
            name: "Phi-2.7B (Q4_0, 1.6 GiB)",
            url: "https://huggingface.co/ggml-org/models/resolve/main/phi-2/ggml-model-q4_0.gguf?download=true",
            filename: "phi-2-q4_0.gguf", status: "download"
        ),

        Model(
            name: "Phi-2.7B (Q8_0, 2.8 GiB)",
            url: "https://huggingface.co/ggml-org/models/resolve/main/phi-2/ggml-model-q8_0.gguf?download=true",
            filename: "phi-2-q8_0.gguf", status: "download"
        ),

        Model(
            name: "Mistral-7B-v0.1 (Q4_0, 3.8 GiB)",
            url: "https://huggingface.co/TheBloke/Mistral-7B-v0.1-GGUF/resolve/main/mistral-7b-v0.1.Q4_0.gguf?download=true",
            filename: "mistral-7b-v0.1.Q4_0.gguf", status: "download"
        ),
        Model(
            name: "OpenHermes-2.5-Mistral-7B (Q3_K_M, 3.52 GiB)",
            url: "https://huggingface.co/TheBloke/OpenHermes-2.5-Mistral-7B-GGUF/resolve/main/openhermes-2.5-mistral-7b.Q3_K_M.gguf?download=true",
            filename: "openhermes-2.5-mistral-7b.Q3_K_M.gguf", status: "download"
        )
    ]
    func loadModel(modelUrl: URL?) throws {
        if let modelUrl {
            #if DEBUG
            print("🔄 [LlamaState] Loading model from: \(modelUrl.path)")
            #endif
            messageLog += "Loading model...\n"
            SystemLog().logEvent(event: "[LlamaState] Loading model: \(modelUrl.lastPathComponent)")

            llamaContext = try LlamaContext.create_context(path: modelUrl.path)

            #if DEBUG
            print("✅ [LlamaState] Model loaded successfully: \(modelUrl.lastPathComponent)")
            #endif
            messageLog += "Loaded model \(modelUrl.lastPathComponent)\n"
            SystemLog().logEvent(event: "[LlamaState] Model loaded: \(modelUrl.lastPathComponent)")

            // モデル/環境情報をログ
            if let llamaContext {
                Task { [weak self] in
                    let info = await llamaContext.system_info()
                    SystemLog().logEvent(event: "[llama] system_info: \(info)")
                    #if DEBUG
                    print("ℹ️ [LlamaState] System info: \(info)")
                    #endif
                    await MainActor.run { self?.messageLog += "system_info captured\n" }
                }
            }

            // プリセット設定を反映
            Task { [weak self] in
                await self?.applyConfigToContext()
            }

            // Assuming that the model is successfully loaded, update the downloaded models
            updateDownloadedModels(modelName: modelUrl.lastPathComponent, status: "downloaded")
        } else {
            #if DEBUG
            print("⚠️ [LlamaState] No model URL provided")
            #endif
            messageLog += "Load a model from the list below\n"
        }
    }


    private func updateDownloadedModels(modelName: String, status: String) {
        undownloadedModels.removeAll { $0.name == modelName }
    }

    // 正規化ユーティリティ（モデル差異に依存しない）
    private func normalizeOutput(_ s: String) -> String {
        // 1) 未クローズ含む<think>を除去
        let withoutThink = s.replacingOccurrences(
            of: "(?is)<think>.*?(</think>|$)",
            with: "",
            options: .regularExpression
        )
        // 2) 制御トークンの掃除
        var t = withoutThink
            .replacingOccurrences(of: "<\\|im_start\\|>assistant", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<\\|im_start\\|>user", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<\\|im_start\\|>system", with: "", options: .regularExpression)
        t = t.components(separatedBy: "<|im_end|>").first ?? t
        t = t.replacingOccurrences(of: "<\\|.*?\\|>", with: "", options: .regularExpression)
        // 3) 見出し的な "assistant:" を除去
        t = t.replacingOccurrences(of: "^assistant:?\\s*", with: "", options: [.regularExpression, .caseInsensitive])
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func complete(text: String) async -> String {
        guard let llamaContext else {
            #if DEBUG
            print("❌ [LlamaState] No llamaContext available!")
            #endif
            SystemLog().logEvent(event: "[LlamaState] ERROR: No llamaContext")
            return ""
        }

        #if DEBUG
        print("🎬 [LlamaState] Starting completion for prompt length: \(text.count)")
        #endif
        SystemLog().logEvent(event: "[LlamaState] Starting completion, promptLen=\(text.count)")

        // 設定を念のため反映（直前に変更がある場合）
        await applyConfigToContext()

        let t_start = DispatchTime.now().uptimeNanoseconds
        await llamaContext.completion_init(text: text)
        let t_heat_end = DispatchTime.now().uptimeNanoseconds
        let t_heat = Double(t_heat_end - t_start) / NS_PER_S

        #if DEBUG
        print("🔥 [LlamaState] Heat up completed in \(String(format: "%.2f", t_heat))s")
        #endif

        await MainActor.run {
            self.messageLog += "USER: \(text)\n"
        }

        var assistantResponse = ""
        // ストリームフィルタ用バッファと状態
        var buffer = ""
        var inThink = false
        var thinkChars: Int = 0
        var thinkStartNS: UInt64? = nil
        let THINK_TIMEOUT_S: Double = 3.0 // iOSでのスタック防止
        let THINK_CHAR_LIMIT = 4000       // 長すぎる思考は打ち切る
        // 全体ウォッチドッグ
        let GENERATION_TIMEOUT_S: Double = 20.0
        let genStartNS = DispatchTime.now().uptimeNanoseconds

        #if DEBUG
        var tokenCount = 0
        var loopCount = 0
        #endif

        while await !llamaContext.is_done {
            #if DEBUG
            loopCount += 1
            #endif

            // 全体タイムアウト
            let genElapsed = Double(DispatchTime.now().uptimeNanoseconds - genStartNS) / NS_PER_S
            if genElapsed > GENERATION_TIMEOUT_S {
                #if DEBUG
                print("⏱️ [LlamaState] Generation timeout after \(String(format: "%.2f", genElapsed))s")
                #endif
                await llamaContext.request_stop()
                break
            }

            // Check for stuck generation (no tokens after many loops)
            #if DEBUG
            if loopCount > 50 && tokenCount == 0 {
                print("⚠️ [LlamaState] WARNING: \(loopCount) loops but no tokens yet!")
            }
            if loopCount > 100 && tokenCount == 0 {
                print("❌ [LlamaState] ERROR: Generation stuck - 100 loops with 0 tokens")
                SystemLog().logEvent(event: "[LlamaState] ERROR: Generation stuck after 100 loops")
                await llamaContext.request_stop()
                break
            }
            #endif

            let chunk = await llamaContext.completion_loop()
            if chunk.isEmpty { continue }

            #if DEBUG
            tokenCount += 1
            if tokenCount == 1 {
                print("🎉 [LlamaState] First token received!")
                SystemLog().logEvent(event: "[LlamaState] First token generated after \(loopCount) loops")
            }
            if tokenCount % 10 == 0 {
                print("📊 [LlamaState] Generated \(tokenCount) tokens...")
            }
            #endif

            buffer += chunk

            // Stopトークン: <|im_end|> で即終了
            if let endIdx = buffer.range(of: "<|im_end|>") {
                let prefix = String(buffer[..<endIdx.lowerBound])
                if !prefix.isEmpty { assistantResponse += prefix }
                await llamaContext.request_stop()
                break
            }

            // streamingで<think>…</think>を除去
            processing: while true {
                if inThink {
                    if let rng = buffer.range(of: "</think>") {
                        let after = buffer[rng.upperBound...]
                        buffer = String(after)
                        inThink = false
                        thinkChars = 0
                        thinkStartNS = nil
                        continue processing
                    } else {
                        thinkChars += buffer.count
                        if thinkStartNS == nil { thinkStartNS = DispatchTime.now().uptimeNanoseconds }
                        let elapsed = (Double((DispatchTime.now().uptimeNanoseconds) - (thinkStartNS ?? 0)) / NS_PER_S)
                        if (elapsed > THINK_TIMEOUT_S || thinkChars > THINK_CHAR_LIMIT) {
                            // 思考ブロックが閉じない -> 強制停止
                            await llamaContext.request_stop()
                            buffer.removeAll(keepingCapacity: true)
                            break
                        }
                        // 継続待ち
                        break processing
                    }
                } else {
                    if let rng = buffer.range(of: "<think>") {
                        let prefix = String(buffer[..<rng.lowerBound])
                        if !prefix.isEmpty { assistantResponse += prefix }
                        buffer = String(buffer[rng.upperBound...])
                        inThink = true
                        thinkChars = 0
                        thinkStartNS = DispatchTime.now().uptimeNanoseconds
                        continue processing
                    } else {
                        assistantResponse += buffer
                        buffer.removeAll(keepingCapacity: true)
                        break processing
                    }
                }
            }
        }

        let t_end = DispatchTime.now().uptimeNanoseconds
        let t_generation = Double(t_end - t_heat_end) / self.NS_PER_S
        let tokens_per_second = Double(await llamaContext.n_len) / t_generation

        #if DEBUG
        print("⏱️ [LlamaState] Generation completed in \(String(format: "%.2f", t_generation))s")
        print("⚡ [LlamaState] Speed: \(String(format: "%.2f", tokens_per_second)) tokens/s")
        print("📊 [LlamaState] Total tokens: \(tokenCount)")
        print("📝 [LlamaState] Raw response length: \(assistantResponse.count)")
        #endif

        await llamaContext.clear()

        // 最終正規化
        let finalAnswer = normalizeOutput(assistantResponse)

        #if DEBUG
        print("✨ [LlamaState] Normalized response length: \(finalAnswer.count)")
        print("📊 [LlamaState] Token metrics: \(tokenCount) tokens in \(loopCount) loops")
        if finalAnswer.isEmpty {
            print("⚠️ [LlamaState] WARNING: Final answer is empty!")
            if tokenCount == 0 {
                print("❌ [LlamaState] ERROR: No tokens were generated!")
            }
        }
        #endif
        SystemLog().logEvent(event: "[LlamaState] Generation complete: \(finalAnswer.count) chars, \(tokenCount) tokens, \(String(format: "%.2f", tokens_per_second)) t/s")

        // Explicit check for empty generation
        if finalAnswer.isEmpty && tokenCount == 0 {
            let errorMsg = "No tokens generated - model may be incompatible or context initialization failed"
            #if DEBUG
            print("❌ [LlamaState] \(errorMsg)")
            #endif
            SystemLog().logEvent(event: "[LlamaState] ERROR: \(errorMsg)")
        }

        await MainActor.run {
            self.messageLog += "ASSISTANT: \(finalAnswer)\n"
            self.messageLog += "\nDone\nHeat up took \(t_heat)s\nGenerated \(tokens_per_second) t/s\n"
        }
        return finalAnswer
    }

    func bench() async {
        guard let llamaContext else {
            return
        }

        messageLog += "\n"
        messageLog += "Running benchmark...\n"
        messageLog += "Model info: "
        messageLog += await llamaContext.model_info() + "\n"

        let t_start = DispatchTime.now().uptimeNanoseconds
        let _ = await llamaContext.bench(pp: 8, tg: 4, pl: 1) // heat up
        let t_end = DispatchTime.now().uptimeNanoseconds

        let t_heat = Double(t_end - t_start) / NS_PER_S
        messageLog += "Heat up time: \(t_heat) seconds, please wait...\n"

        // if more than 5 seconds, then we're probably running on a slow device
        if t_heat > 5.0 {
            messageLog += "Heat up time is too long, aborting benchmark\n"
            return
        }

        let result = await llamaContext.bench(pp: 512, tg: 128, pl: 1, nr: 3)

        messageLog += "\(result)"
        messageLog += "\n"
    }

    func clear() async {
        guard let llamaContext else {
            return
        }

        await llamaContext.clear()
        messageLog = ""
    }
}
