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

// Import the shared model management components
#if canImport(NoesisNoema_Shared)
import NoesisNoema_Shared
#else
// For direct compilation, include the source files
// This assumes the shared files are accessible in the build
#endif

// Fast path: handle `model` subcommands via shared ModelCLI before running the harness
if CommandLine.arguments.count >= 2 && CommandLine.arguments[1].lowercased() == "model" {
    Task {
        var subArgs = CommandLine.arguments
        // remove the 'model' token so that args[1] becomes the actual command (e.g., 'test')
        subArgs.remove(at: 1)
        let code = await ModelCLI.handleCommand(subArgs)
        exit(Int32(code))
    }
    dispatchMain()
}

// Fast path: handle `rag` subcommands via shared RagCLI before running the harness
if CommandLine.arguments.count >= 2 && CommandLine.arguments[1].lowercased() == "rag" {
    Task {
        var subArgs = CommandLine.arguments
        // remove the 'rag' token so that args[1] becomes the actual command (e.g., 'retrieve')
        subArgs.remove(at: 1)
        let code = await RagCLI.handleCommand(subArgs)
        exit(Int32(code))
    }
    dispatchMain()
}

// New: run internal tests without XCTest
if CommandLine.arguments.count >= 2 && CommandLine.arguments[1].lowercased() == "tests" {
    Task {
        let code = await TestRunner.runAllTests()
        exit(Int32(code))
    }
    dispatchMain()
}

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

/// Search for a model file, supporting both flat and nested directory structures
/// (llama.cpp v0.2.0+ expects Models/<modelName>/*.gguf)
func findModelInDirectory(_ baseDir: String, modelName: String, fm: FileManager) -> String? {
    // Try direct file first (flat structure)
    let directPath = "\(baseDir)/\(modelName)"
    if fm.fileExists(atPath: directPath) {
        return directPath
    }

    // Try nested: Models/<modelName>/*.gguf
    let modelNameWithoutExt = (modelName as NSString).deletingPathExtension
    let nestedDir = "\(baseDir)/\(modelNameWithoutExt)"
    if fm.fileExists(atPath: nestedDir) {
        do {
            let contents = try fm.contentsOfDirectory(atPath: nestedDir)
            if let ggufFile = contents.first(where: { $0.hasSuffix(".gguf") }) {
                return "\(nestedDir)/\(ggufFile)"
            }
        } catch {
            // Directory not accessible, continue
        }
    }

    return nil
}

func candidateModelPaths(fileName: String) -> [String] {
    let fm = FileManager.default
    let cwd = fm.currentDirectoryPath
    var paths: [String] = []

    print("🔍 [CLI] Starting model search for: \(fileName)")
    print("   CWD: \(cwd)")

    // Define base directories to search
    var baseDirs: [String] = []

    // 1) CWD + project structure
    baseDirs.append("\(cwd)/NoesisNoema/NoesisNoema/Resources/Models")
    baseDirs.append("\(cwd)/NoesisNoema/Resources/Models")
    baseDirs.append("\(cwd)/Resources/Models")
    baseDirs.append("\(cwd)/Models")

    // 2) Absolute project path
    baseDirs.append("/Users/raskolnikoff/Xcode Projects/NoesisNoema/NoesisNoema/Resources/Models")

    // 3) Bundle resources
    if let r = Bundle.main.resourceURL {
        baseDirs.append(r.appendingPathComponent("Models").path)
        baseDirs.append(r.appendingPathComponent("Resources/Models").path)
        baseDirs.append(r.path)
    }

    // 4) Executable directory
    let exePath = CommandLine.arguments[0]
    let exeDir = URL(fileURLWithPath: exePath).deletingLastPathComponent().path
    baseDirs.append("\(exeDir)/Models")
    baseDirs.append("\(exeDir)/Resources/Models")

    // 5) Downloads
    #if !targetEnvironment(macCatalyst)
    if let home = FileManager.default.homeDirectoryForCurrentUser.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
        let decoded = home.removingPercentEncoding ?? home
        baseDirs.append("\(decoded)/Downloads")
    }
    #else
    let homeDir = NSHomeDirectory()
    baseDirs.append("\(homeDir)/Downloads")
    #endif

    // Search each base directory
    for baseDir in LinkedHashSet(baseDirs) {
        if let found = findModelInDirectory(baseDir, modelName: fileName, fm: fm) {
            paths.append(found)
        }
    }

    // Fallback: direct paths (for backwards compatibility)
    paths.append("\(cwd)/\(fileName)")
    paths.append("./\(fileName)")

    print("   Generated \(paths.count) candidate paths")
    return Array(LinkedHashSet(paths))
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

// Quick utility: print OOM-like defaults (approx) without app types
func printDefaultsAndExit() -> Never {
    let cores = ProcessInfo.processInfo.processorCount
    let memGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024*1024*1024)
    let threads = max(1, min(cores - 1, 8))
    #if os(macOS)
    let ctx: UInt32 = memGB >= 16 ? 8192 : (memGB >= 8 ? 4096 : 2048)
    let batch: UInt32 = memGB >= 16 ? 1024 : (memGB >= 8 ? 512 : 256)
    #else
    let ctx: UInt32 = memGB >= 8 ? 4096 : (memGB >= 6 ? 2048 : 1024)
    let batch: UInt32 = memGB >= 8 ? 512 : (memGB >= 6 ? 256 : 128)
    #endif
    let gpuLayers = memGB >= 16 ? 999 : (memGB >= 8 ? 80 : 40)
    let memLimitMB = memGB >= 16 ? 4096 : (memGB >= 8 ? 2048 : 1024)
    print("📊 OOM-Safe Defaults (approx without app types):")
    print("   CPU Cores: \(cores)")
    print(String(format: "   Total Memory: %.1f GB", memGB))
    print("   → Recommended Threads: \(threads)")
    print("   → Context Size: \(ctx)")
    print("   → Batch Size: \(batch)")
    print("   → Memory Limit: \(memLimitMB) MB")
    print("   → GPU Layers: \(gpuLayers)")
    exit(0)
}

func printDemoAndExit() -> Never {
    print("🚀 NoesisNoema Model Registry Demonstration (lite)")
    print(String(repeating: "=", count: 60))
    print("")
    printDefaultsAndExit()
}

// Flag-only modes (no model load)
if CommandLine.arguments.contains("--defaults") { printDefaultsAndExit() }
if CommandLine.arguments.contains("--demo") { printDemoAndExit() }

// ============================================================
// MODEL PATH RESOLUTION
// ============================================================
print("=== LlamaBridgeTest CLI ===")
print("📋 Discovered LLM name: \(defaultModelFileName)")

var modelPath: String?
var matchedIndex: Int? = nil

if let explicit = cli.modelPath {
    print("🔧 Explicit model path provided: \(explicit)")
    if fm.fileExists(atPath: explicit) {
        modelPath = explicit
        print("✅ Explicit path validated")
    } else {
        fputs("❌ ERROR: Explicit path does not exist: \(explicit)\n", stderr)
        exit(2)
    }
} else {
    print("🔍 Auto-detecting model location...")
    print("")

    let candidates = candidateModelPaths(fileName: defaultModelFileName)

    if candidates.isEmpty {
        fputs("❌ ERROR: No candidate paths generated. This is a bug.\n", stderr)
        exit(2)
    }

    print("   Checking \(candidates.count) candidate paths:")
    for (index, p) in candidates.enumerated() {
        let exists = fm.fileExists(atPath: p)
        let status = exists ? "✅ FOUND" : "❌ not found"
        print("   \(index + 1). \(status)")
        print("      \(p)")

        if exists && modelPath == nil {
            modelPath = p
            matchedIndex = index + 1
        }
    }

    if modelPath != nil, let idx = matchedIndex {
        print("")
        print("✅ Model auto-detected at candidate #\(idx)")
    } else {
        print("")
        fputs("❌ ERROR: Model file not found in any candidate location.\n", stderr)
        fputs("\n", stderr)
        fputs("   Searched: \(candidates.count) locations\n", stderr)
        fputs("   Model name: \(defaultModelFileName)\n", stderr)
        fputs("\n", stderr)
        fputs("   Hint: Use -m /absolute/path/to/\(defaultModelFileName)\n", stderr)
        fputs("         or place the model in one of:\n", stderr)
        fputs("         - ./Resources/Models/\n", stderr)
        fputs("         - ./NoesisNoema/Resources/Models/\n", stderr)
        fputs("         - ~/Downloads/\n", stderr)
        exit(2)
    }
}

guard let modelPath else {
    fputs("❌ FATAL: modelPath is nil after resolution. This should not happen.\n", stderr)
    exit(2)
}

print("")
print("═══════════════════════════════════════════════════════════")
print("📂 RESOLVED MODEL PATH:")
print("   \(modelPath)")

let fileSize = try? fm.attributesOfItem(atPath: modelPath)[.size] as? UInt64
if let size = fileSize {
    let sizeMB = Double(size) / (1024 * 1024)
    let sizeGB = sizeMB / 1024
    if sizeGB >= 1.0 {
        print("   Size: \(String(format: "%.2f", sizeGB)) GB (\(String(format: "%.0f", sizeMB)) MB)")
    } else {
        print("   Size: \(String(format: "%.1f", sizeMB)) MB")
    }
}
print("═══════════════════════════════════════════════════════════")
print("")

// Default prompt if none provided
let promptText = cli.prompt ?? "What is Retrieval-Augmented Generation (RAG)? Answer in 2 sentences. If unknown, say 'I don't know.'"
let fullPrompt = cli.usePlainTemplate ? buildPlainPrompt(question: promptText) : buildPrompt(question: promptText)

// 自動プリセット決定（未指定 or auto の場合）
autoPresetAdjust(&cli, modelPath: modelPath, prompt: promptText)
applyPreset(&cli)
print("PRESET: \(cli.preset ?? "(none)") temp=\(cli.temp) topK=\(cli.topK) topP=\(cli.topP) nLen=\(cli.nLen)")

// ============================================================
// LLAMA CONTEXT INITIALIZATION
// ============================================================
Task {
    do {
        print("🔧 Initializing llama_context...")
        print("   Model path: \(modelPath)")

        let ctx = try LlamaContext.create_context(path: modelPath)

        print("✅ llama_context created successfully")
        print("")

        print("🎛️  Configuring sampling parameters...")
        await ctx.set_verbose(cli.verbose)
        await ctx.configure_sampling(temp: cli.temp, top_k: cli.topK, top_p: cli.topP, seed: cli.seed)
        await ctx.set_n_len(cli.nLen)
        print("   Temperature: \(cli.temp)")
        print("   Top-K: \(cli.topK)")
        print("   Top-P: \(cli.topP)")
        print("   Max tokens: \(cli.nLen)")
        print("✅ Sampling configured")
        print("")

        func infer(_ prompt: String) async -> String {
            print("🚀 Starting inference...")
            print("   Prompt length: \(prompt.count) characters")
            print("")

            await ctx.completion_init(text: prompt)
            print("✅ Prompt processed, beginning token generation...")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🔄 TOKEN STREAM:")
            print("")

            var acc = ""
            var buffer = ""
            var inThink = false
            var tokenCount = 0

            while await !ctx.is_done {
                let chunk = await ctx.completion_loop()
                if chunk.isEmpty { continue }

                tokenCount += 1
                if tokenCount == 1 {
                    print("   ✅ First token received")
                }
                if tokenCount % 10 == 0 {
                    print("   [Token \(tokenCount)]")
                }

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

            print("")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("✅ Token generation complete")
            print("   Total tokens: \(tokenCount)")
            print("   Raw output length: \(acc.count) characters")
            print("")

            let cleaned = cleanOutput(acc)
            if cleaned.isEmpty {
                print("⚠️  Output is empty after cleaning")
                return ""
            }

            print("   Cleaned output length: \(cleaned.count) characters")
            return cleaned
        }

        print("🎯 Running inference with \(cli.usePlainTemplate ? "plain" : "chat") template...")
        print("")

        var finalOut = await infer(fullPrompt)

        if finalOut.isEmpty && !cli.usePlainTemplate {
            print("")
            print("ℹ️  Empty output detected, retrying with plain prompt template...")
            print("")
            finalOut = await infer(buildPlainPrompt(question: promptText))
        }

        if finalOut.isEmpty {
            print("")
            fputs("❌ WARN: Model returned empty content.\n", stderr)
            fputs("   Possible causes:\n", stderr)
            fputs("   - Template mismatch with model format\n", stderr)
            fputs("   - Model immediately hit stop token\n", stderr)
            fputs("   - Try: --plain flag for plain template\n", stderr)
            fputs("   - Try: different model with -m flag\n", stderr)
            print("")
        } else {
            print("")
            print("═══════════════════════════════════════════════════════════")
            print("📝 FINAL OUTPUT:")
            print("═══════════════════════════════════════════════════════════")
            print(finalOut)
            print("═══════════════════════════════════════════════════════════")
            print("")
        }
    } catch {
        print("")
        print("═══════════════════════════════════════════════════════════")
        fputs("❌ ERROR during inference pipeline:\n", stderr)
        fputs("   \(error)\n", stderr)
        print("═══════════════════════════════════════════════════════════")
        print("")
    }
    exit(0)
}

dispatchMain() // Keep CLI alive until async task finishes
