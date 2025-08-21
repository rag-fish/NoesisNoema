// Project: NoesisNoema
// File: LLMModel.swift
// Created by Раскольников on 2025/07/20.
// Description: Defines the LLMModel class for handling large language models.
// License: MIT License

import Foundation

class LLMModel: @unchecked Sendable {
    
    /**
        * Represents a large language model (LLM) with its properties and methods.
        *
        * - Properties:
        *   - name: The name of the model.
        *   - modelFile: The file containing the model.
        *   - version: The version of the model.
        *   - isEmbedded: A boolean indicating if the model is embedded.
        */
    var name: String
    
    /**
        * The file containing the model.
        * This file is used to load the model's configuration and weights.
        */
    var modelFile: String
    
    /**
        * The version of the model.
        * This is used to ensure compatibility with other components.
        */
    var version: String
    
    /**
        * Indicates whether the model is embedded.
        * This is used to determine if the model can be used directly or needs to be loaded from a file.
        */
    var isEmbedded: Bool

    /**
        * Initializes an LLMModel with the specified properties.
        * - Parameter name: The name of the model.
        * - Parameter modelFile: The file containing the model.
        * - Parameter version: The version of the model.
        * - Parameter isEmbedded: A boolean indicating if the model is embedded.
     
     */
    init(name: String, modelFile: String, version: String, isEmbedded: Bool = false) {
        self.name = name
        self.modelFile = modelFile
        self.version = version
        self.isEmbedded = isEmbedded
    }
    
    /**
        * Generates a response based on the provided prompt.
        * - Parameter prompt: The input text to generate a response for.
        * - Returns: A string containing the generated response.
        */
    func generate(prompt: String) -> String {
        return generate(prompt: prompt, context: nil)
    }

    /// 文脈（RAGなど）を注入して生成する
    func generate(prompt: String, context: String?) -> String {
        return runInference(userText: prompt, context: context)
    }

    // 生成本体（共通）
    private func runInference(userText: String, context: String?) -> String {
        // Jan 向けテンプレート/クリーニングを適用
        func buildJanPrompt(_ question: String, context: String? = nil) -> String {
            let sys = """
            You are Noesis/Noema on-device assistant.
            Answer with the final answer only. Do not include analysis, chain-of-thought, self-talk, internal monologue, or meta commentary.
            Never output tags like <think>...</think>, <analysis>, or planning notes. If you start to write such content, stop and output only the final answer.
            """
            var user = "Question: \(question)"
            if let ctx = context, !ctx.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                user += "\nContext:\n\(ctx)"
            }
            return """
            <|im_start|>system
            \(sys)
            <|im_end|>
            <|im_start|>user
            \(user)
            <|im_end|>
            <|im_start|>assistant
            """
        }
        func buildPlainPrompt(_ question: String, context: String? = nil) -> String {
            let sys = """
            You are a helpful, concise assistant.
            Answer with the final answer only. Do not include analysis, chain-of-thought, self-talk, internal monologue, or meta commentary.
            Never output tags like <think>...</think>. If tempted, stop and give only the final answer.
            """
            var txt = sys + "\n\n"
            if let ctx = context, !ctx.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                txt += "Context:\n\(ctx)\n\n"
            }
            txt += "Question: \(question)\n\nAnswer:"
            return txt
        }
        func cleanOutput(_ s: String) -> String {
            // 1) 未クローズ含む<think>ブロックの全削除
            //   - 閉じタグがない場合でも末尾まで除去
            let withoutThink = s.replacingOccurrences(
                of: "(?is)<think>.*?(</think>|$)",
                with: "",
                options: .regularExpression
            )
            // 2) 先頭のチャット制御タグ除去
            var t = withoutThink
                .replacingOccurrences(of: "<\\|im_start\\|>assistant", with: "")
                .replacingOccurrences(of: "<\\|im_start\\|>user", with: "")
                .replacingOccurrences(of: "<\\|im_start\\|>system", with: "")
            // 3) assistantターンの終了タグで打ち切り
            t = t.components(separatedBy: "<|im_end|>").first ?? t
            // 4) 万一の残存制御トークンを軽く掃除
            t = t.replacingOccurrences(of: "<\\|.*?\\|>", with: "", options: .regularExpression)
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let fileName = self.modelFile.isEmpty ? "Jan-v1-4B-Q4_K_M.gguf" : self.modelFile
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        var checkedPaths: [String] = []

        // 1) CWD
        let pathCWD = "\(cwd)/\(fileName)"
        checkedPaths.append(pathCWD)

        // 2) 実行ファイルディレクトリ
        let exePath = CommandLine.arguments[0]
        let exeDir = URL(fileURLWithPath: exePath).deletingLastPathComponent().path
        let pathExeDir = "\(exeDir)/\(fileName)"
        if pathExeDir != pathCWD { checkedPaths.append(pathExeDir) }

        // 3) App Bundle 内
        if let bundleResourceURL = Bundle.main.resourceURL {
            let pathBundle = bundleResourceURL.appendingPathComponent(fileName).path
            if pathBundle != pathCWD && pathBundle != pathExeDir { checkedPaths.append(pathBundle) }
            let subdirs = ["Models", "Resources/Models", "Resources", "NoesisNoema/Resources/Models"]
            for sub in subdirs {
                let p = bundleResourceURL.appendingPathComponent(sub).appendingPathComponent(fileName).path
                if !checkedPaths.contains(p) { checkedPaths.append(p) }
            }
        }
        // 4) リソース検索
        let nameNoExt = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        let bundleLookups: [String?] = [
            Bundle.main.url(forResource: nameNoExt, withExtension: ext, subdirectory: nil)?.path,
            Bundle.main.url(forResource: nameNoExt, withExtension: ext, subdirectory: "Models")?.path,
            Bundle.main.url(forResource: nameNoExt, withExtension: ext, subdirectory: "Resources/Models")?.path,
            Bundle.main.url(forResource: nameNoExt, withExtension: ext, subdirectory: "Resources")?.path
        ]
        for bp in bundleLookups.compactMap({ $0 }) {
            if !checkedPaths.contains(bp) { checkedPaths.append(bp) }
        }

        for path in checkedPaths {
            if fm.fileExists(atPath: path) {
                let semaphore = DispatchSemaphore(value: 0)
                var result = ""
                Task {
                    let llamaState = await LlamaState()
                    do {
                        try await llamaState.loadModel(modelUrl: URL(fileURLWithPath: path))
                        // 自動/手動プリセットの決定と適用
                        let userPreset = ModelManager.shared.currentLLMPreset
                        if userPreset != "auto" {
                            await llamaState.setPreset(userPreset)
                        } else {
                            var intentText = "Question: \(userText)"
                            if let ctx = context, !ctx.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                intentText += "\nContext:\n\(ctx)"
                            }
                            let preset = await llamaState.autoSelectPreset(modelFileName: fileName, prompt: intentText)
                            await llamaState.setPreset(preset.rawValue)
                        }

                        let isJan = self.name.lowercased().contains("jan") || fileName.lowercased().contains("jan")
                        let primaryPrompt = isJan ? buildJanPrompt(userText, context: context) : buildPlainPrompt(userText, context: context)
                        var response: String = await llamaState.complete(text: primaryPrompt)
                        var cleaned = cleanOutput(response)
                        let needsFallback = cleaned.isEmpty || cleaned.contains("<think>") || cleaned.contains("<|im_") || cleaned.lowercased().hasPrefix("assistant")
                        if needsFallback {
                            response = await llamaState.complete(text: buildPlainPrompt(userText, context: context))
                            cleaned = cleanOutput(response)
                        }
                        result = cleaned.isEmpty ? response : cleaned
                    } catch {
                        result = "[LLMModel] 推論エラー: \(error)"
                    }
                    semaphore.signal()
                }
                semaphore.wait()
                return result
            }
        }
        return "[LLMModel] モデルファイルが見つかりません: \(fileName)"
    }

    /**
        * Loads the model from the specified file.
        * - Parameter file: The file to load the model from.
        */
    func loadModel(file: Any) -> Void {
        // 実際はモデルファイルをロードするが、ここではダミー実装
        print("Loading LLM model from file: \(file)")
        self.isEmbedded = true
        self.modelFile = String(describing: file)
        print("Model loaded: \(name), version: \(version), file: \(modelFile)")
    }
}
