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
        default:
            continue
        }
    }
    return cli
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
let cli = parseArgs()
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
let promptText = cli.prompt ?? "What is Retrieval-Augmented Generation (RAG)? Answer in 2 sentences."
let fullPrompt = cli.usePlainTemplate ? buildPlainPrompt(question: promptText) : buildPrompt(question: promptText)

// === LlamaState integration ===
Task {
    // Replace with your actual wrapper init if it needs configuration
    let llama = await LlamaState()
    do {
        try await llama.loadModel(modelUrl: URL(fileURLWithPath: modelPath))

        // Recommended runtime knobs (enable if your wrapper supports them):
        // llama.ngl = 999                    // Prefer full Metal offload on Apple devices
        // llama.threads = 6                  // Tune to CPU cores
        // llama.contextLength = 4096
        // llama.stop = ["<|im_end|>", "<think>", "</think>"]

        // Small helper to run one completion and apply cleaning/fallback
        func infer(_ prompt: String) async -> String {
            let raw: String = await llama.complete(text: prompt)
            let cleaned = cleanOutput(raw)
            let fallback = raw.trimmingCharacters(in: .whitespacesAndNewlines)
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
