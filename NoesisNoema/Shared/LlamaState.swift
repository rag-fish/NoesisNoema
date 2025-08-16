import Foundation

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
            messageLog += "Loading model...\n"
            llamaContext = try LlamaContext.create_context(path: modelUrl.path)
            messageLog += "Loaded model \(modelUrl.lastPathComponent)\n"

            // モデル/環境情報をログ
            if let llamaContext {
                Task { [weak self] in
                    let info = await llamaContext.system_info()
                    SystemLog().logEvent(event: "[llama] system_info: \(info)")
                    await MainActor.run { self?.messageLog += "system_info captured\n" }
                }
            }

            // Assuming that the model is successfully loaded, update the downloaded models
            updateDownloadedModels(modelName: modelUrl.lastPathComponent, status: "downloaded")
        } else {
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
        guard let llamaContext else { return "" }

        let t_start = DispatchTime.now().uptimeNanoseconds
        await llamaContext.completion_init(text: text)
        let t_heat_end = DispatchTime.now().uptimeNanoseconds
        let t_heat = Double(t_heat_end - t_start) / NS_PER_S

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

        while await !llamaContext.is_done {
            let chunk = await llamaContext.completion_loop()
            if chunk.isEmpty { continue }
            buffer += chunk

            // Stopトークン: <|im_end|> で即終了
            if let endIdx = buffer.range(of: "<|im_end|>") {
                // 終了タグ以前のテキストを取り出し
                let prefix = String(buffer[..<endIdx.lowerBound])
                if !prefix.isEmpty { assistantResponse += prefix }
                await llamaContext.request_stop()
                break
            }

            // streamingで<think>…</think>を除去
            processing: while true {
                if inThink {
                    if let rng = buffer.range(of: "</think>") {
                        // </think> までスキップ
                        let after = buffer[rng.upperBound...]
                        buffer = String(after)
                        inThink = false
                        thinkChars = 0
                        thinkStartNS = nil
                        // ループを続行して外側テキストの抽出へ
                        continue processing
                    } else {
                        // 終了タグがまだ来ない -> しきい値監視しつつ次チャンクを待つ
                        thinkChars += buffer.count
                        if thinkStartNS == nil { thinkStartNS = DispatchTime.now().uptimeNanoseconds }
                        let elapsed = (Double((DispatchTime.now().uptimeNanoseconds) - (thinkStartNS ?? 0)) / NS_PER_S)
                        if (elapsed > THINK_TIMEOUT_S || thinkChars > THINK_CHAR_LIMIT) && assistantResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            // 早期終了: これ以上待たない
                            break
                        }
                        // バッファは保持（タグ跨ぎ対応）
                        break processing
                    }
                } else {
                    if let rng = buffer.range(of: "<think>") {
                        // think開始までを出力
                        let prefix = String(buffer[..<rng.lowerBound])
                        if !prefix.isEmpty { assistantResponse += prefix }
                        // think状態へ
                        buffer = String(buffer[rng.upperBound...])
                        inThink = true
                        thinkChars = 0
                        thinkStartNS = DispatchTime.now().uptimeNanoseconds
                        // 継続して</think>探索
                        continue processing
                    } else {
                        // thinkが無ければ全て出力してバッファクリア
                        assistantResponse += buffer
                        buffer.removeAll(keepingCapacity: true)
                        break processing
                    }
                }
            }

            // もし早期終了条件でbreakした場合、外のwhileも抜ける
            if inThink {
                let elapsed = thinkStartNS.map { Double(DispatchTime.now().uptimeNanoseconds - $0) / NS_PER_S } ?? 0
                if (elapsed > THINK_TIMEOUT_S || thinkChars > THINK_CHAR_LIMIT) && assistantResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    break
                }
            }
        }

        let t_end = DispatchTime.now().uptimeNanoseconds
        let t_generation = Double(t_end - t_heat_end) / self.NS_PER_S
        let tokens_per_second = Double(await llamaContext.n_len) / t_generation

        await llamaContext.clear()

        // 最終正規化
        let finalAnswer = normalizeOutput(assistantResponse)

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
