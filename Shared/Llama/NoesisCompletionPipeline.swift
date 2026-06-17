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

    // Step 1: Prompt assembly is DEFERRED to after context creation. The
    // token-budget manager (Step 3.5) needs the model tokenizer to size RAG
    // context and chat history against the real KV budget (n_ctx − n_len)
    // rather than a char estimate.

    // Step 2: Create LlamaContext (fresh, like CLI does)
    print("🔧 [NoesisCompletion] Creating LlamaContext...")
    let ctxStart = Date()
    let ctx = try LlamaContext.create_context(path: modelPath)
    let ctxTime = Date().timeIntervalSince(ctxStart)
    print("✅ [NoesisCompletion] LlamaContext created successfully in \(String(format: "%.2f", ctxTime*1000))ms")
    SystemLog().logEvent(event: String(format: "[PERF] Context creation: %.2f ms", ctxTime*1000))

    #if DEBUG
    // n_ctx footprint harness: record effective n_ctx + "both models loaded"
    // footprint now that the generator KV cache is allocated (embedder is
    // already resident from the retrieval that ran before this call). Inert
    // unless the harness armed the probe.
    let _harnessEffectiveNCtx = await ctx.n_ctx()
    NctxHarnessProbe.shared.noteContextCreated(effectiveNCtx: Int(_harnessEffectiveNCtx))
    #endif

    // Step 3: Configure sampling (matches CLI)
    print("🎛️  [NoesisCompletion] Configuring sampling...")
    await ctx.set_verbose(params.verbose)
    await ctx.configure_sampling(temp: params.temp, top_k: params.topK, top_p: params.topP, seed: params.seed)
    await ctx.set_n_len(params.nLen)
    print("✅ [NoesisCompletion] Sampling configured")

    // Step 3.5: Token-budget manager — the SINGLE accounting point for prompt
    // assembly. BOTH on-device generation paths converge here:
    //   • ModelManager.generateAsyncAnswer → LLMModel.generateAsync → here
    //   • HybridExecutionCoordinator → LocalExecutor → LLMModel.generateAsync → here
    // It allocates n_ctx − n_len across the question (always whole), RAG context
    // (trimmed only if needed), and chat history (newest-first), so a multi-turn
    // conversation can never overflow the KV cache — instead of rejecting an
    // over-budget prompt, we trim history (then RAG) to fit. completion_init's
    // PR #111 reserve guard remains as the last-resort backstop.
    let promptStart = Date()
    let budgeted = await assembleBudgetedPrompt(
        question: question,
        context: context,
        history: history,
        ctx: ctx,
        nLen: Int(params.nLen)
    )
    let promptTime = Date().timeIntervalSince(promptStart)
    guard budgeted.fits else {
        // Only reachable when the question itself + generation reserve cannot
        // fit n_ctx (impossible at n_ctx=4096 for any real question). Surface a
        // clear error instead of hanging — no history/RAG trim can rescue this.
        SystemLog().logEvent(event: "[NoesisCompletion] budget: question + n_len reserve exceeds n_ctx — cannot answer")
        return "The question is too long for the model's context window. Try a shorter question."
    }
    let prompt = budgeted.prompt
    print("📝 [NoesisCompletion] Budgeted prompt built: \(prompt.count) chars in \(String(format: "%.2f", promptTime*1000))ms")
    print("[RAG] prompt preview:", String(prompt.prefix(200)))
    SystemLog().logEvent(event: String(format: "[PERF] Prompt build (budgeted): %.2f ms", promptTime*1000))

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
        #if DEBUG
        // n_ctx harness: record the over-budget bail so the table shows where a
        // level overflows. promptTokens unknown here (init aborted pre-decode).
        NctxHarnessProbe.shared.recordGeneration(NctxLatencySample(
            promptEvalMs: Date().timeIntervalSince(tokenizeStart) * 1000,
            decodeMs: 0, totalMs: Date().timeIntervalSince(perfStart) * 1000,
            genTokens: 0, promptTokens: 0, bailed: true))
        #endif
        // Over-budget prompt (or decode failure) — skip the generation loop
        // entirely and return a user-visible message instead of hanging.
        return "The question exceeded the model's context window. " +
               "Try a shorter question or clear chat history."
    }
    let tokenizeTime = Date().timeIntervalSince(tokenizeStart)
    #if DEBUG
    // Prefill / time-to-first-token proxy = completion_init duration (the single
    // decode over the whole prompt). n_cur now equals the prompt token count.
    let _harnessPromptTokens = Int(await ctx.current_n_cur())
    let _harnessPromptEvalMs = tokenizeTime * 1000
    let _harnessDecodeStart = Date()
    #endif
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

            // detect <|eot_id|> but DO NOT discard previous data
            if let endTag = buffer.range(of: "<|eot_id|>") {
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

    #if DEBUG
    // n_ctx harness: decode wall-clock = generation loop only (prefill already
    // captured as promptEvalMs; cleanup below is excluded).
    let _harnessDecodeMs = Date().timeIntervalSince(_harnessDecodeStart) * 1000
    #endif

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

    #if DEBUG
    // n_ctx harness: record this question's latency. decodeMs is the generation
    // loop only (prefill excluded); tok/s is derived from it in the report.
    NctxHarnessProbe.shared.recordGeneration(NctxLatencySample(
        promptEvalMs: _harnessPromptEvalMs,
        decodeMs: _harnessDecodeMs,
        totalMs: totalTime * 1000,
        genTokens: tokenCount,
        promptTokens: _harnessPromptTokens,
        bailed: false))
    #endif

    print("✅ [NoesisCompletion] Final answer: \(finalAnswer.count) chars")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("📊 [PERF] Total pipeline time: \(String(format: "%.2f", totalTime*1000))ms")
    SystemLog().logEvent(event: String(format: "[NoesisCompletion] Complete: %d tokens, %d chars, %.2f ms total", tokenCount, finalAnswer.count, totalTime*1000))
    SystemLog().logEvent(event: String(format: "[PERF] Cleanup: %.2f ms", cleanTime*1000))

    return finalAnswer
}

// MARK: - Helper Functions (from CLI)

/// Build the Llama-3 chat prompt for `runNoesisCompletion`.
///
/// The active generator is Llama-3.2-3B-Instruct, which expects the Llama-3
/// chat template (`<|begin_of_text|>` / `<|start_header_id|>role<|end_header_id|>`
/// / `<|eot_id|>`). Emitting ChatML (`<|im_start|>`/`<|im_end|>`) here made the
/// model see unknown tokens and immediately emit EOS — generating a single
/// token. This now renders the Llama-3 format.
///
/// ADR-0009: prior turns (already filtered/capped by the UI to ≤3 turns
/// within a 45-minute window) are emitted as additional Llama-3 turns
/// BETWEEN the system prompt and the current question. The system prompt
/// appears once at the top. Retrieved `Context` is attached to the CURRENT
/// user turn only — history turns are reproduced verbatim with no retrieval
/// baggage. Empty history ⇒ output identical to the single-turn build.
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

    // Llama-3 template: each prior turn is a user/assistant header pair, both
    // terminated by <|eot_id|>. Rendered via `renderHistoryTurn` so the
    // token-budget manager counts each turn against the EXACT bytes emitted here.
    var historyTurns = ""
    for turn in history {
        historyTurns += renderHistoryTurn(turn)
    }

    let prompt = "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(sys)<|eot_id|>"
        + historyTurns
        + "<|start_header_id|>user<|end_header_id|>\n\n\(user)<|eot_id|>"
        + "<|start_header_id|>assistant<|end_header_id|>\n\n"
    #if DEBUG
    print("🧠 [SESSION-MEM/PROMPT] final prompt length=\(prompt.count) chars")
    print("🧠 [SESSION-MEM/PROMPT] prompt full (first 1500 chars):\n\(String(prompt.prefix(1500)))")
    #endif
    return prompt
}

/// Render one prior turn as the Llama-3 user/assistant header pair, exactly as
/// `buildPrompt` concatenates it. Shared so the token-budget manager counts the
/// SAME bytes that get decoded.
func renderHistoryTurn(_ turn: ConversationTurn) -> String {
    return "<|start_header_id|>user<|end_header_id|>\n\n\(turn.question)<|eot_id|>"
        + "<|start_header_id|>assistant<|end_header_id|>\n\n\(turn.answer)<|eot_id|>"
}

/// Result of token-budget prompt assembly.
struct BudgetedPrompt {
    let prompt: String
    /// False ⇒ even question + generation reserve cannot fit n_ctx; caller errors.
    let fits: Bool
}

/// Assemble the generation prompt within the KV budget (n_ctx − n_len).
///
/// This is the token-budget MANAGER and the single owner of prompt assembly for
/// the on-device pipeline. It tokenizes with the model's real tokenizer (via
/// `LlamaContext.token_count`) and allocates the budget in priority order —
/// question (whole) → RAG (trim if needed) → history (newest-first) — using the
/// pure `ContextBudget.allocate` seam. An assemble-measure-adjust safety pass
/// absorbs tokenizer boundary effects so completion_init's KV guard never trips.
func assembleBudgetedPrompt(
    question: String,
    context: String?,
    history: [ConversationTurn],
    ctx: LlamaContext,
    nLen: Int
) async -> BudgetedPrompt {
    let nCtx = Int(await ctx.n_ctx())

    // Mandatory skeleton: system + current question turn (no context) + header.
    let mandatoryRender = buildPrompt(question: question, context: nil, history: [])
    let mandatoryTokens = await ctx.token_count(mandatoryRender)

    // RAG cost = (render with full context) − mandatory skeleton.
    let hasRag = !((context?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ?? true)
    let ragTokens: Int
    if hasRag {
        let ragRender = buildPrompt(question: question, context: context, history: [])
        ragTokens = max(0, await ctx.token_count(ragRender) - mandatoryTokens)
    } else {
        ragTokens = 0
    }

    // Per-turn history token cost, NEWEST FIRST.
    let newestFirst = Array(history.reversed())
    var historyTokensNewestFirst: [Int] = []
    historyTokensNewestFirst.reserveCapacity(newestFirst.count)
    for turn in newestFirst {
        historyTokensNewestFirst.append(await ctx.token_count(renderHistoryTurn(turn)))
    }

    let plan = ContextBudget.allocate(
        nCtx: nCtx,
        nLen: nLen,
        mandatoryTokens: mandatoryTokens,
        ragTokens: ragTokens,
        historyTurnTokensNewestFirst: historyTokensNewestFirst
    )

    guard plan.mandatoryFits else {
        return BudgetedPrompt(prompt: mandatoryRender, fits: false)
    }

    // Trim RAG context to its granted token budget when it didn't all fit.
    var finalContext = context
    if hasRag && plan.ragTrimmed {
        finalContext = await truncateContextToTokens(
            context ?? "",
            grantedTokens: plan.ragGrantedTokens,
            question: question,
            mandatoryTokens: mandatoryTokens,
            ctx: ctx
        )
    }

    // Keep the newest N history turns, restored to chronological order.
    var keptHistory = Array(Array(newestFirst.prefix(plan.keptHistoryCount)).reversed())

    var prompt = buildPrompt(question: question, context: finalContext, history: keptHistory)
    let budget = plan.promptBudget

    // Safety net for tokenizer boundary effects (component counts are not
    // perfectly additive): drop oldest kept turns, then shrink RAG, until the
    // measured prompt fits. Guarantees nPrompt ≤ n_ctx − n_len.
    var promptTokens = await ctx.token_count(prompt)
    while promptTokens > budget && !keptHistory.isEmpty {
        keptHistory.removeFirst() // drop oldest kept turn
        prompt = buildPrompt(question: question, context: finalContext, history: keptHistory)
        promptTokens = await ctx.token_count(prompt)
    }
    if promptTokens > budget && hasRag {
        let overflow = promptTokens - budget
        let target = max(0, plan.ragGrantedTokens - overflow - 8) // 8-token margin
        finalContext = await truncateContextToTokens(
            context ?? "",
            grantedTokens: target,
            question: question,
            mandatoryTokens: mandatoryTokens,
            ctx: ctx
        )
        prompt = buildPrompt(question: question, context: finalContext, history: keptHistory)
        promptTokens = await ctx.token_count(prompt)
    }

    SystemLog().logEvent(event:
        "[NoesisCompletion] budget: n_ctx=\(nCtx) reserve(n_len)=\(nLen) promptBudget=\(budget) | "
        + "question+system mandatory=\(mandatoryTokens)tk | "
        + "RAG=\(plan.ragGrantedTokens)/\(plan.ragRequestedTokens)tk\(plan.ragTrimmed ? " (trimmed)" : "") | "
        + "history kept=\(keptHistory.count)/\(history.count) dropped=\(history.count - keptHistory.count) | "
        + "final prompt=\(promptTokens)tk (fits=\(promptTokens <= budget))")

    return BudgetedPrompt(prompt: prompt, fits: true)
}

/// Binary-search the longest character prefix of `context` whose RAG token cost
/// (render-with-context minus mandatory skeleton) fits `grantedTokens`. Uses the
/// same `buildPrompt` rendering the model decodes, so the count is exact.
func truncateContextToTokens(
    _ context: String,
    grantedTokens: Int,
    question: String,
    mandatoryTokens: Int,
    ctx: LlamaContext
) async -> String {
    if grantedTokens <= 0 || context.isEmpty { return "" }

    func ragCost(_ candidate: String) async -> Int {
        if candidate.isEmpty { return 0 }
        let render = buildPrompt(question: question, context: candidate, history: [])
        return max(0, await ctx.token_count(render) - mandatoryTokens)
    }

    if await ragCost(context) <= grantedTokens { return context }

    let chars = Array(context)
    var lo = 0, hi = chars.count, best = 0
    while lo <= hi {
        let mid = (lo + hi) / 2
        let candidate = String(chars[0..<mid])
        if await ragCost(candidate) <= grantedTokens {
            best = mid
            lo = mid + 1
        } else {
            hi = mid - 1
        }
    }
    return String(chars[0..<best])
}

private func cleanOutput(_ s: String) -> String {
    // Step 1: Remove all <think>...</think> blocks
    var out = s.replacingOccurrences(of: "(?s)<think>.*?</think>", with: "", options: .regularExpression)

    // Step 2: Extract only the last assistant block if present (Llama-3 headers)
    let assistantPattern = "(?s)<\\|start_header_id\\|>assistant<\\|end_header_id\\|>\\s*(.*?)(?:<\\|eot_id\\|>|$)"
    if let regex = try? NSRegularExpression(pattern: assistantPattern, options: []),
       let matches = regex.matches(in: out, options: [], range: NSRange(out.startIndex..., in: out)) as [NSTextCheckingResult]?,
       !matches.isEmpty {
        if let lastMatch = matches.last,
           lastMatch.numberOfRanges >= 2,
           let contentRange = Range(lastMatch.range(at: 1), in: out) {
            out = String(out[contentRange])
        }
    }

    // Step 3: Strip Llama-3 special tokens / residue
    for token in ["<|begin_of_text|>", "<|eot_id|>", "<|start_header_id|>", "<|end_header_id|>"] {
        out = out.replacingOccurrences(of: token, with: "")
    }
    // Leftover header role labels (e.g. a dangling "assistant" / "user")
    out = out.replacingOccurrences(of: "^(?:system|user|assistant)\\b", with: "", options: [.regularExpression])
    // Any remaining broken special-token fragments and stray "|>"
    out = out.replacingOccurrences(of: "<\\|[a-z_]*\\|?>?", with: "", options: .regularExpression)
    out = out.replacingOccurrences(of: "\\|>", with: "", options: .regularExpression)

    // Step 4: Trim
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
