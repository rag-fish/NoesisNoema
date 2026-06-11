//
//  NoesisCompletionPipeline.swift
//  NoesisNoema
//
//  Unified completion pipeline extracted from working CLI
//  This is the authoritative inference flow for all platforms (CLI/macOS/iOS)
//

import Foundation

/// Runtime parameters for LLM inference
public struct LlamaRuntimeParams {
    var temp: Float
    var topK: Int32
    var topP: Float
    var seed: UInt64
    var nLen: Int32
    var verbose: Bool

    public init(temp: Float = 0.7, topK: Int32 = 60, topP: Float = 0.9, seed: UInt64 = 1234, nLen: Int32 = 512, verbose: Bool = false) {
        self.temp = temp
        self.topK = topK
        self.topP = topP
        self.seed = seed
        self.nLen = nLen
        self.verbose = verbose
    }

    public static let balanced = LlamaRuntimeParams(temp: 0.5, topK: 60, topP: 0.9, nLen: 512)
    public static let factual = LlamaRuntimeParams(temp: 0.2, topK: 40, topP: 0.85, nLen: 384)
    public static let creative = LlamaRuntimeParams(temp: 0.9, topK: 100, topP: 0.95, nLen: 768)
}

/// Unified completion pipeline - the SINGLE source of truth for inference
/// Extracted from working CLI (LlamaBridgeTest/main.swift)
/// ⚠️ NO @MainActor - must run on background thread to avoid blocking UI
/// PERFORMANCE: Runs entirely off main thread
public func runNoesisCompletion(
    question: String,
    context: String?,
    modelPath: String,
    params: LlamaRuntimeParams = .balanced,
    history: [ConversationTurn] = []
) async throws -> String {

    let perfStart = Date()

    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("🎬🎬🎬 [NoesisCompletion] UNIFIED PIPELINE ENTRY 🎬🎬🎬")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("   Question: \(question.prefix(80))...")
    print("   Context: \(context != nil ? "\(context!.count) chars" : "none")")
    print("   Model: \(modelPath)")
    print("   Params: temp=\(params.temp) topK=\(params.topK) topP=\(params.topP) nLen=\(params.nLen)")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    SystemLog().logEvent(event: "[NoesisCompletion] Starting pipeline: q=\(question.count)chars ctx=\(context?.count ?? 0)chars")

    // Step 1: Build prompt (matches CLI logic)
    let promptStart = Date()
    let prompt = buildPrompt(question: question, context: context, history: history)
    let promptTime = Date().timeIntervalSince(promptStart)
    print("📝 [NoesisCompletion] Prompt built: \(prompt.count) chars in \(String(format: "%.2f", promptTime*1000))ms")
    SystemLog().logEvent(event: String(format: "[PERF] Prompt build: %.2f ms", promptTime*1000))

    // RAG diagnostic: Show prompt preview (as requested in issue)
    print("[RAG] prompt preview:", String(prompt.prefix(200)))

    // Step 2: Create LlamaContext (fresh, like CLI does)
    print("🔧 [NoesisCompletion] Creating LlamaContext...")
    let ctxStart = Date()
    let ctx = try LlamaContext.create_context(path: modelPath)
    let ctxTime = Date().timeIntervalSince(ctxStart)
    print("✅ [NoesisCompletion] LlamaContext created successfully in \(String(format: "%.2f", ctxTime*1000))ms")
    SystemLog().logEvent(event: String(format: "[PERF] Context creation: %.2f ms", ctxTime*1000))

    // Step 3: Configure sampling (matches CLI)
    print("🎛️  [NoesisCompletion] Configuring sampling...")
    await ctx.set_verbose(params.verbose)
    await ctx.configure_sampling(temp: params.temp, top_k: params.topK, top_p: params.topP, seed: params.seed)
    await ctx.set_n_len(params.nLen)
    print("✅ [NoesisCompletion] Sampling configured")

    // Step 4: Initialize completion (tokenize prompt)
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("🚀 [NoesisCompletion] BEFORE completion_init()")
    print("   Prompt length: \(prompt.count)")
    print("   Prompt preview: \(prompt.prefix(200))...")
    let tokenizeStart = Date()
    let initOK = await ctx.completion_init(text: prompt)
    if !initOK {
        let err = await ctx.get_last_error() ?? "unknown init error"
        print("⚠️ [NoesisCompletion] completion_init bailed: \(err)")
        // Over-budget prompt (or decode failure) — skip the generation loop
        // entirely and return a user-visible message instead of hanging.
        return "The question exceeded the model's context window. " +
               "Try a shorter question or clear chat history."
    }
    let tokenizeTime = Date().timeIntervalSince(tokenizeStart)
    print("✅ [NoesisCompletion] AFTER completion_init() - Prompt tokenized in \(String(format: "%.2f", tokenizeTime*1000))ms")
    SystemLog().logEvent(event: String(format: "[PERF] Tokenization: %.2f ms", tokenizeTime*1000))
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("🔄 ENTERING TOKEN GENERATION LOOP")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    // Step 5: Token generation loop (EXACT copy from CLI)
    var acc = ""
    var buffer = ""
    var inThink = false
    var tokenCount = 0
    var loopIterations = 0

    print("🔄 [NoesisCompletion] Starting while loop...")
    while await !ctx.is_done {
        loopIterations += 1
        if loopIterations <= 3 {
            print("   Loop iteration #\(loopIterations): calling completion_loop()...")
        }
        let chunk = await ctx.completion_loop()
        if loopIterations <= 3 {
            print("   Loop iteration #\(loopIterations): got chunk of length \(chunk.count)")
        }
        if chunk.isEmpty { continue }

        tokenCount += 1
        if tokenCount == 1 {
            print("🎉 [NoesisCompletion] First token received!")
        }
        if tokenCount % 10 == 0 {
            print("   [\(tokenCount) tokens...]")
        }

        buffer += chunk

        // Processing logic (matches CLI exactly)
        processing: while true {
            // skip think blocks
            if inThink {
                if let end = buffer.range(of: "</think>") {
                    buffer = String(buffer[end.upperBound...])
                    inThink = false
                    continue processing
                } else {
                    break processing
                }
            }

            // detect <think>
            if let start = buffer.range(of: "<think>") {
                let prefix = String(buffer[..<start.lowerBound])
                if !prefix.isEmpty { acc += prefix }
                buffer = String(buffer[start.upperBound...])
                inThink = true
                continue processing
            }

            // detect <|im_end|> but DO NOT discard previous data
            if let endTag = buffer.range(of: "<|im_end|>") {
                let prefix = String(buffer[..<endTag.lowerBound])
                if !prefix.isEmpty { acc += prefix }
                await ctx.request_stop()
                buffer.removeAll()
                break processing
            }

            // no special markers — flush buffer into acc
            acc += buffer
            buffer.removeAll()
            break processing
        }
    }

    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("✅ [NoesisCompletion] EXITED TOKEN LOOP")
    print("   Loop iterations: \(loopIterations)")
    print("   Tokens generated: \(tokenCount)")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    // flush any non-think residue
    if !buffer.isEmpty && !inThink { acc += buffer }

    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("✅ [NoesisCompletion] Token generation complete")
    print("   Total tokens: \(tokenCount)")
    print("   Raw output: \(acc.count) chars")
    print("   Raw preview: \(acc.prefix(200))...")

    // Step 6: Clean output (matches CLI)
    let cleanStart = Date()
    let cleaned = cleanOutput(acc)
    let finalAnswer = extractFinalAnswer(cleaned)
    let cleanTime = Date().timeIntervalSince(cleanStart)

    let totalTime = Date().timeIntervalSince(perfStart)

    print("✅ [NoesisCompletion] Final answer: \(finalAnswer.count) chars")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("📊 [PERF] Total pipeline time: \(String(format: "%.2f", totalTime*1000))ms")
    SystemLog().logEvent(event: String(format: "[NoesisCompletion] Complete: %d tokens, %d chars, %.2f ms total", tokenCount, finalAnswer.count, totalTime*1000))
    SystemLog().logEvent(event: String(format: "[PERF] Cleanup: %.2f ms", cleanTime*1000))

    return finalAnswer
}

// MARK: - Helper Functions (from CLI)

/// Build the ChatML prompt for `runNoesisCompletion`.
///
/// ADR-0009: prior turns (already filtered/capped by the UI to ≤3 turns
/// within a 45-minute window) are emitted as additional ChatML turns
/// BEFORE the current question. The system prompt appears once at the top.
/// Retrieved `Context` is attached to the CURRENT user turn only — history
/// turns are reproduced verbatim with no retrieval baggage. Empty history
/// ⇒ output identical to the prior single-turn build. The chat template
/// itself (ChatML) is unchanged — that question is parked separately.
///
/// Made `internal` (was `private`) so source-level tests can verify the
/// rendered prompt without invoking the model.
func buildPrompt(
    question: String,
    context: String?,
    history: [ConversationTurn] = []
) -> String {
    #if DEBUG
    print("🧠 [SESSION-MEM/PROMPT] buildPrompt entered; history.count=\(history.count)")
    #endif
    let sys = """
    You are Noesis/Noema on-device RAG assistant.
    Answer questions using the provided context.
    Be concise and direct. Do not include meta-commentary or analysis.
    """
    var user = "Question: \(question)"
    if let ctx = context, !ctx.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        user += "\n\nContext:\n\(ctx)"
    } else {
        print("⚠️ [buildPrompt] WARNING: No context provided - answering without RAG")
    }

    var historyTurns = ""
    for turn in history {
        historyTurns += """
        <|im_start|>user
        \(turn.question)
        <|im_end|>
        <|im_start|>assistant
        \(turn.answer)
        <|im_end|>

        """
    }

    let prompt = """
    <|im_start|>system
    \(sys)
    <|im_end|>
    \(historyTurns)<|im_start|>user
    \(user)
    <|im_end|>
    <|im_start|>assistant
    """
    #if DEBUG
    print("🧠 [SESSION-MEM/PROMPT] final prompt length=\(prompt.count) chars")
    print("🧠 [SESSION-MEM/PROMPT] prompt full (first 1500 chars):\n\(String(prompt.prefix(1500)))")
    #endif
    return prompt
}

private func cleanOutput(_ s: String) -> String {
    // Step 1: Remove all <think>...</think> blocks
    var out = s.replacingOccurrences(of: "(?s)<think>.*?</think>", with: "", options: .regularExpression)

    // Step 2: Remove broken fragments
    out = out.replacingOccurrences(of: "<\\|im(?:_[a-z]+)?", with: "", options: .regularExpression)
    out = out.replacingOccurrences(of: "</im[^>]*", with: "", options: .regularExpression)
    out = out.replacingOccurrences(of: "<im[^>]*", with: "", options: .regularExpression)

    // Step 3: Extract only the last assistant block if present
    let assistantPattern = "(?s)<\\|im_start\\|>assistant\\s*(.*?)(?:<\\|im_end\\|>|$)"
    if let regex = try? NSRegularExpression(pattern: assistantPattern, options: []),
       let matches = regex.matches(in: out, options: [], range: NSRange(out.startIndex..., in: out)) as [NSTextCheckingResult]?,
       !matches.isEmpty {
        if let lastMatch = matches.last,
           lastMatch.numberOfRanges >= 2,
           let contentRange = Range(lastMatch.range(at: 1), in: out) {
            out = String(out[contentRange])
        }
    }

    // Step 4: Remove any remaining tags
    out = out.replacingOccurrences(of: "<\\|im_start\\|>[^<]*", with: "", options: .regularExpression)
    out = out.replacingOccurrences(of: "<\\|im_end\\|>", with: "", options: .regularExpression)

    // Step 5: Trim
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func extractFinalAnswer(_ s: String) -> String {
    let metaPatterns = [
        "history of previous interactions",
        "we are given",
        "analysis",
        "chain-of-thought",
        "meta-commentary",
        "reasoning",
        "step-by-step",
        "let me",
        "i will",
        "first,",
        "second,",
        "finally,"
    ]

    let lines = s.components(separatedBy: .newlines)
    let filteredLines = lines.filter { line in
        let lower = line.lowercased()
        return !metaPatterns.contains(where: { lower.contains($0) })
    }

    let filtered = filteredLines.joined(separator: "\n")
    let paragraphs = filtered.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    if let longestParagraph = paragraphs.max(by: { $0.count < $1.count }),
       longestParagraph.count > 20 {
        return longestParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let result = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? s.trimmingCharacters(in: .whitespacesAndNewlines) : result
}
