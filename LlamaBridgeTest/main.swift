//
//  main.swift
//  LlamaBridgeTest
//
//  Description: CLI test harness for the Llama.cpp interoperability layer used by Noesis/Noema.
//  This version adds: simple arg parsing (-m, -p), robust model path lookup, Qwen/Jan-style prompt,
//  minimal runtime defaults (threads/ngl placeholders), and output cleanup for <think> tags.
//
//  Usage examples:
//    LlamaBridgeTest -m /path/to/Jan-v1-4B-Q4_K_M.gguf -p "Say hello."
//    LlamaBridgeTest -p "What is RAG?"   // model auto-lookup
//
//  Note:
//    If your LlamaState wrapper supports runtime knobs (threads/ngl/ctx/stop), wire them below
//    in the marked section. Otherwise this harness simply loads and completes with defaults.
//

import Foundation

// MARK: - CLI Args
struct CLI {
    var modelPath: String?
    var prompt: String?
    var usePlainTemplate: Bool = false
    // sampling / runtime
    var temp: Float = 0.7
    var topK: Int32 = 60
    var topP: Float = 0.9
    var seed: UInt64 = 1234
    var nLen: Int32 = 512
    var verbose: Bool = false
    var preset: String? = nil
}

func parseArgs() -> CLI {
    var cli = CLI(modelPath: nil, prompt: nil, usePlainTemplate: false)
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        switch arg {
        case "-m", "--model":
            cli.modelPath = it.next()
        case "-p", "--prompt":
            cli.prompt = it.next()
        case "-q", "--quick":
            cli.prompt = "Say a short hello in one sentence."
        case "--plain":
            cli.usePlainTemplate = true
        case "--preset":
            cli.preset = it.next()?.lowercased()
        case "--temp":
            if let v = it.next(), let f = Float(v) { cli.temp = f }
        case "--top-k":
            if let v = it.next(), let i = Int32(v) { cli.topK = i }
        case "--top-p":
            if let v = it.next(), let f = Float(v) { cli.topP = f }
        case "--seed":
            if let v = it.next(), let u = UInt64(v) { cli.seed = u }
        case "-n", "--n-len":
            if let v = it.next(), let i = Int32(v) { cli.nLen = i }
        case "-v", "--verbose":
            cli.verbose = true
        default:
            continue
        }
    }
    return cli
}

// プリセット適用
func applyPreset(_ cli: inout CLI) {
    guard let name = cli.preset else { return }
    switch name {
    case "factual":
        // 事実系・RAG向け（低温度・やや狭い探索）
        cli.temp = 0.2
        cli.topK = 40
        cli.topP = 0.85
        cli.nLen = 384
    case "balanced":
        cli.temp = 0.5
        cli.topK = 60
        cli.topP = 0.9
        cli.nLen = 512
    case "creative":
        cli.temp = 0.9
        cli.topK = 100
        cli.topP = 0.95
        cli.nLen = 768
    case "json":
        // 構造化出力想定。温度低め＋プレーンテンプレート
        cli.temp = 0.2
        cli.topK = 40
        cli.topP = 0.9
        cli.nLen = 512
        cli.usePlainTemplate = true
    case "code":
        // コード/手順。やや低温度、探索は標準
        cli.temp = 0.3
        cli.topK = 50
        cli.topP = 0.9
        cli.nLen = 640
    default:
        fputs("Unknown preset: \(name). Available: factual, balanced, creative, json, code\n", stderr)
    }
}

// 簡易インテント検出（RAG/JSON/コード/創造/汎用）
func detectIntent(prompt: String) -> String {
    let p = prompt.lowercased()
    // RAG/コンテキスト
    if p.contains("context:") || p.contains("reference:") || p.contains("資料:") { return "factual" }
    // JSON出力
    if p.contains("json") || p.contains("return json") || p.contains("出力はjson") || p.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") { return "json" }
    // コード気配
    if p.contains("```") || p.contains("code") || p.contains("swift") || p.contains("python") || p.contains("関数") || p.contains("コード") { return "code" }
    // 創造的タスク
    if p.contains("story") || p.contains("poem") || p.contains("creative") || p.contains("アイデア") { return "creative" }
    return "balanced"
}

// モデル名＋インテントで自動プリセット選択
func autoPresetAdjust(_ cli: inout CLI, modelPath: String, prompt: String) {
    // 明示指定があるなら何もしない
    if let preset = cli.preset, preset != "auto" { return }

    let fn = URL(fileURLWithPath: modelPath).lastPathComponent.lowercased()
    var intent = detectIntent(prompt: prompt)

    // モデル特性で微調整
    if fn.contains("jan") || fn.contains("qwen") {
        // Janは事実/JSONに向く傾向
        if intent == "balanced" { intent = "factual" }
    } else if fn.contains("llama3") {
        // Llama3は汎用 → balanced 既定
        if intent == "factual" { intent = "balanced" }
    } else if fn.contains("mistral") || fn.contains("phi") || fn.contains("tinyllama") {
        // 小型モデルは温度低めが安定
        if intent == "creative" { intent = "balanced" }
    }

    cli.preset = intent
}

// MARK: - Paths
let defaultModelFileName = "Jan-v1-4B-Q4_K_M.gguf" // development default

func candidateModelPaths(fileName: String) -> [String] {
    let fm = FileManager.default
    let cwd = fm.currentDirectoryPath
    var paths: [String] = []

    // 1) CWD
    paths.append("\(cwd)/\(fileName)")

    // 2) Executable directory
    let exePath = CommandLine.arguments[0]
    let exeDir = URL(fileURLWithPath: exePath).deletingLastPathComponent().path
    if exeDir != cwd { paths.append("\(exeDir)/\(fileName)") }

    // 3) Bundle resources (rare in CLI, but handy when run inside Xcode)
    if let r = Bundle.main.resourceURL { paths.append(r.appendingPathComponent(fileName).path) }

    // 4) Conventional places (adjust as needed in your workspace)
    paths.append("./Resources/Models/\(fileName)")
    paths.append("./NoesisNoema/Resources/Models/\(fileName)")

    // 5) User downloads (convenience)
    if let home = FileManager.default.homeDirectoryForCurrentUser.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
        let decoded = home.removingPercentEncoding ?? home
        paths.append("\(decoded)/Downloads/\(fileName)")
    }
    return Array(LinkedHashSet(paths)) // preserve order, drop dups
}

// Poor-man linked hash set for unique-preserving order
struct LinkedHashSet<T: Hashable>: Sequence {
    private var seen = Set<T>()
    private var items: [T] = []
    init(_ input: [T]) {
        for e in input where !seen.contains(e) { seen.insert(e); items.append(e) }
    }
    func makeIterator() -> IndexingIterator<[T]> { items.makeIterator() }
}

// MARK: - Prompt (Qwen/Jan style chat template)
func buildPrompt(question: String, context: String? = nil) -> String {
    let sys = """
    You are Noesis/Noema on-device RAG assistant.
    Answer with the final answer only. Do not include analysis, chain-of-thought, self-talk, or meta-commentary.
    If you are about to write analysis or planning, stop and output only the final answer.
    When context is provided, use only that context.
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

// プレーン（タグなし）テンプレート: モデルのチャットフォーマットに依存しない最低限の指示
func buildPlainPrompt(question: String, context: String? = nil) -> String {
    let sys = """
    You are a helpful, concise assistant.
    Answer with the final answer only. Do not include chain-of-thought.
    """
    var txt = sys + "\n\n"
    if let ctx = context, !ctx.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        txt += "Context:\n\(ctx)\n\n"
    }
    txt += "Question: \(question)\n\nAnswer:"
    return txt
}

func cleanOutput(_ s: String) -> String {
    // 1) Drop any <think>...</think> internal monologue blocks if present
    let withoutThink = s.replacingOccurrences(of: "(?s)<think>.*?</think>", with: "", options: .regularExpression)

    // 2) For Jan/Qwen-style chat templates, cut at <|im_end|> (assistant turn terminator)
    let cutAtEnd = withoutThink.components(separatedBy: "<|im_end|>").first ?? withoutThink

    // 3) Trim whitespace/newlines
    return cutAtEnd.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Main
let cli0 = parseArgs()
var cli = cli0
let fm = FileManager.default

// Resolve model path
var modelPath: String?
if let explicit = cli.modelPath, fm.fileExists(atPath: explicit) {
    modelPath = explicit
} else {
    for p in candidateModelPaths(fileName: defaultModelFileName) {
        if fm.fileExists(atPath: p) { modelPath = p; break }
    }
}

print("=== LlamaBridgeTest ===")
if modelPath == nil { print("Model auto-lookup candidates (not found):") }
for p in candidateModelPaths(fileName: defaultModelFileName) { print("  - \(p)") }

guard let modelPath else {
    fputs("\nERROR: Could not locate model file.\n  Hint: pass -m /absolute/path/to/Jan-v1-4B-Q4_K_M.gguf or place it in one of the listed paths.\n", stderr)
    exit(2)
}
print("USING MODEL: \(modelPath)")

// Default prompt if none provided
let promptText = cli.prompt ?? "What is Retrieval-Augmented Generation (RAG)? Answer in 2 sentences. If unknown, say 'I don't know.'"
let fullPrompt = cli.usePlainTemplate ? buildPlainPrompt(question: promptText) : buildPrompt(question: promptText)

// 自動プリセット決定（未指定 or auto の場合）
autoPresetAdjust(&cli, modelPath: modelPath, prompt: promptText)
applyPreset(&cli)
print("PRESET: \(cli.preset ?? "(none)") temp=\(cli.temp) topK=\(cli.topK) topP=\(cli.topP) nLen=\(cli.nLen)")

// === LlamaState integration ===
Task {
    do {
        // 直接 LlamaContext を使用してモデル読み込みと推論を実施（shim 経由・llama_* 直接呼び出しはしない）
        let ctx = try LlamaContext.create_context(path: modelPath)
        await ctx.set_verbose(cli.verbose)
        await ctx.configure_sampling(temp: cli.temp, top_k: cli.topK, top_p: cli.topP, seed: cli.seed)
        await ctx.set_n_len(cli.nLen)

        func infer(_ prompt: String) async -> String {
            await ctx.completion_init(text: prompt)
            var acc = ""
            var buffer = ""
            var inThink = false
            while await !ctx.is_done {
                let chunk = await ctx.completion_loop()
                if chunk.isEmpty { continue }
                buffer += chunk

                // streaming processing
                processing: while true {
                    if inThink {
                        if let rng = buffer.range(of: "</think>") {
                            // drop until end tag
                            buffer = String(buffer[rng.upperBound...])
                            inThink = false
                            continue processing
                        } else {
                            // wait for more
                            break processing
                        }
                    } else {
                        // stop at assistant end token
                        if let end = buffer.range(of: "<|im_end|>") {
                            let prefix = String(buffer[..<end.lowerBound])
                            if !prefix.isEmpty { acc += prefix }
                            await ctx.request_stop()
                            buffer.removeAll(keepingCapacity: true)
                            break processing
                        }
                        if let rng = buffer.range(of: "<think>") {
                            let prefix = String(buffer[..<rng.lowerBound])
                            if !prefix.isEmpty { acc += prefix }
                            buffer = String(buffer[rng.upperBound...])
                            inThink = true
                            continue processing
                        } else {
                            acc += buffer
                            buffer.removeAll(keepingCapacity: true)
                            break processing
                        }
                    }
                }
            }
            // flush any non-think residue
            if !buffer.isEmpty && !inThink { acc += buffer }

            let cleaned = cleanOutput(acc)
            let fallback = acc.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? fallback : cleaned
        }

        var finalOut = await infer(fullPrompt)
        if finalOut.isEmpty && !cli.usePlainTemplate {
            fputs("\nINFO: Empty output; retrying with plain prompt... Use --plain to force this mode.\n", stderr)
            finalOut = await infer(buildPlainPrompt(question: promptText))
        }
        if finalOut.isEmpty {
            fputs("\nWARN: Model returned empty content (template mismatch or immediate stop). Try providing a different model or --plain.\n", stderr)
        }
        print("\n---\nModel completion:\n\(finalOut)\n")
    } catch {
        fputs("ERROR running inference: \(error)\n", stderr)
    }
    exit(0)
}

dispatchMain() // Keep CLI alive until async task finishes
