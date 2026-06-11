---
date: 2026-06-11
author: claude-code
pr_context: post-#103 UAT
scope: read-only investigation
---

# Dispatch path & RAG retrieval bypass — static investigation

**Read-only.** No `.swift` file, no `project.pbxproj`, and no behaviour was changed. The only artifact is this report. Where a diagnostic `print` or a fix would help, it is *described*, never added.

The question being answered: in the post-#103 Spinoza UAT, Q3 reached `LLMModel.generateAsync` with `Context: none` even though `LocalExecutor.execute(history-aware)` was entered — yet the PR #103 `🔎 [LocalExecutor/RAG]` trace lines never appeared. Why?

---

## Section 1 — Confirm PR #103's prints are on `main` and in the right place

`git log --oneline -5 main`:

```
8170f1f chore(diag): trace retrieval state at the LocalExecutor boundary (UAT diagnostic) (#103)
9f506c6 fix(llama): bail on KV-cache overflow + propagate decode failure (UAT blocker) (#102)
86b1d2b fix(registry): exclude embedder GGUF from LLM selection (UAT blocker) (#101)
9b753d8 fix(rag): chunks.json is [String], citations.jsonl carries metadata (ADR-0011 §5) (#100)
bc47829 fix(rag): tolerant decode for informational manifest blocks (indexer/chunker) (#99)
```

PR #103 (`8170f1f`) is the tip of `main`. `git show 8170f1f --stat` confirms it touches exactly one file, `Shared/Runtime/Executors/LocalExecutor.swift`, `+14` lines, and the commit body states: *"No behavior change… Not #if DEBUG gated so the lines appear in any UAT build configuration."*

### The three print blocks

`Shared/Runtime/Executors/LocalExecutor.swift:81-83` (block 1 — store/query/topK):

```swift
        print("🔎 [LocalExecutor/RAG] store-state: VectorStore.shared.chunks.count=\(VectorStore.shared.chunks.count)")
        print("🔎 [LocalExecutor/RAG] query: \"\(query.prefix(120))\"")
        print("🔎 [LocalExecutor/RAG] topK=\(defaultTopK), useDeepSearch=\(UserDefaults.standard.bool(forKey: Self.deepSearchDefaultsKey))")
```

`Shared/Runtime/Executors/LocalExecutor.swift:103-109` (block 2 — retrieved count + preview):

```swift
        print("🔎 [LocalExecutor/RAG] retrieved chunks.count=\(chunks.count)")
        if let first = chunks.first {
            let preview = first.content.prefix(120).replacingOccurrences(of: "\n", with: " ")
            print("🔎 [LocalExecutor/RAG] chunk[0] preview: \"\(preview)\"")
        } else {
            print("🔎 [LocalExecutor/RAG] no chunks retrieved — context will be empty")
        }
```

`Shared/Runtime/Executors/LocalExecutor.swift:114` (block 3 — joined context length):

```swift
        print("🔎 [LocalExecutor/RAG] context length=\(context.count) chars (chunks joined)")
```

### Are they inside a conditional / early-return scope?

**No.** All three are at the top level of `execute(query:sessionId:history:)`, on a single linear path. Reading `LocalExecutor.swift:70-134`, between the entry print at line 76 and the `generateAsync` call at line 126 there is **no `return`, no `throw`, and no `if` that wraps the prints**. The sequence is strictly:

1. `:76` `🧠 [SESSION-MEM/EXEC] … entered` (`#if DEBUG`)
2. `:79` `let traceId = UUID()`
3. `:81-83` **🔎 block 1 (unconditional)**
4. `:91-101` `await Task.detached { … }.value` (retrieval — awaited, no branch skips it)
5. `:103-109` **🔎 block 2 (unconditional)**
6. `:112` build `context`
7. `:114` **🔎 block 3 (unconditional)**
8. `:124` `🧠 [SESSION-MEM/EXEC] calling generateAsync` (`#if DEBUG`)
9. `:126` `model.generateAsync(…)`

**This is the crux.** The UAT log contains both `🧠` lines (steps 1 and 8) but none of the `🔎` lines (steps 3, 5, 7) that sit *between* them on the same straight-line path. There is no code path in current source that can execute lines 76 and 124 while skipping 81–114.

### All `execute(...)` methods on `LocalExecutor`

| # | Signature | File:line | Role |
|---|-----------|-----------|------|
| 1 | `func execute(query: String, sessionId: UUID) async throws -> ExecutionResult` | `LocalExecutor.swift:51-59` | Stateless overload — only logs `🧠 …(stateless) entered`, then delegates to #2 with `[]`. |
| 2 | `func execute(query: String, sessionId: UUID, history: [ConversationTurn]) async throws -> ExecutionResult` | `LocalExecutor.swift:70-149` | **History-aware. Contains all three 🔎 blocks. This is the one the Coordinator calls.** |

The `Executor` protocol (`ExecutorProtocol.swift:18-62`) declares both `execute(query:sessionId:)` (`:26`) and `execute(query:sessionId:history:)` (`:43`) **as protocol requirements**, plus a default extension implementation of the history-aware one (`:55-61`) that drops history and calls the stateless overload.

The Coordinator would handle a request via **method #2**. `HybridExecutionCoordinator.swift:199-203` calls `executor.execute(query:sessionId:history:)` through an `Executor` existential. Because the history-aware method is a *protocol requirement* (not extension-only), the call dynamically dispatches to `LocalExecutor`'s override (method #2), **not** the extension default. The presence of `🧠 [SESSION-MEM/EXEC] LocalExecutor.execute(history-aware) entered` in the log proves method #2 ran — so there is no protocol-extension shadowing bug here (a real Swift hazard, but ruled out because the method is a witnessed requirement).

---

## Section 2 — All call sites that reach `LLMModel.generateAsync(...)`

There is exactly **one** definition: `LLMModel.generateAsync(prompt:context:history:)` at `Shared/LLMModel.swift:51`. (`ModelManager.generateAsyncAnswer` and the test mock are different methods.) Three call sites invoke it:

| # | File:line | Caller | `context` passed | Class/actor chain leading here |
|---|-----------|--------|------------------|--------------------------------|
| 1 | `LocalExecutor.swift:126-130` | `LocalExecutor.execute(query:sessionId:history:)` | `context.isEmpty ? nil : context`, where `context` = retrieved `chunks.map{$0.content}.joined("\n\n")` (`:112`); **`history:` passed** | `DesktopChatView.startAsk` → `HybridExecutionCoordinator.execute` → `LocalExecutor.execute(…history:)` → `LLMModel.generateAsync` |
| 2 | `ModelManager.swift:390` | `ModelManager.generateAsyncAnswer(question:)` | `context.isEmpty ? nil : context`, where `context` = retrieved `chunks.map{…}.joined` (`:353`); **no `history` arg → defaults to `[]`** | (a) `ExecutionCoordinator.executeLocal` → `ModelManager.generateAsyncAnswer` → `LLMModel.generateAsync`; **and** (b) `ContentView.askRAG` (`ContentView.swift:444`) → `ModelManager.generateAsyncAnswer` → `LLMModel.generateAsync` |
| 3 | `LLMModel.swift:37` | `LLMModel.generate(prompt:context:)` (sync `DispatchSemaphore` wrapper, marked DEPRECATED) | forwards its own `context` param; no `history` | Legacy synchronous callers of `LLMModel.generate(...)` |

The `🎬 [LLMModel] generateAsync ENTRY POINT` in the UAT log is emitted at `LLMModel.swift:57`, common to all three call sites. The `Context: none` line is `LLMModel.swift:61` (`context != nil ? … : "none"`), and `[RAG] context length: 0` is `LLMModel.swift:84`. Both fire whenever the caller passed `nil` (i.e. an empty joined context).

---

## Section 3 — Request path for a Q3-style question (macOS)

**Hop 1 — UI.** `Apps/macOS/NoesisNoema/Views/DesktopChatView.swift:261-269`:

```swift
        let history = SessionMemory.history(from: documentManager.qaHistory)

        Task { @MainActor in
            do {
                let response = try await executionCoordinator.execute(
                    request: NoemaRequest(query: trimmed, history: history)
                )
```

`executionCoordinator` defaults to `HybridExecutionCoordinator()` (`DesktopChatView.swift:50`; same in `DesktopRootView.swift:105` and `Shared/NoesisNoemaApp.swift:18`). History is derived from the *visible transcript* and the current question is appended only **after** the response returns (`addQAPair`, `DesktopChatView.swift:271`).

**Hop 2 — Coordinator dispatch decision.** `Shared/Runtime/Execution/HybridExecutionCoordinator.swift:142-145` decides local vs cloud; there is **no "with RAG vs without RAG" decision here** — RAG is unconditional inside `LocalExecutor`:

```swift
        // Step 6: Select executor.
        let executor: Executor = routingDecision.routeTarget == .local
            ? localExecutor
            : agentExecutor
```

then `HybridExecutionCoordinator.swift:199-203`:

```swift
            result = try await executor.execute(
                query: request.query,
                sessionId: request.sessionId,
                history: request.history
            )
```

**Hop 3 — LocalExecutor retrieval.** The retrieval invocation is `Shared/Runtime/Executors/LocalExecutor.swift:91-101`:

```swift
        let chunks = await Task.detached(priority: .userInitiated) {
            if useDeepSearch {
                var config = DeepSearch.Config()
                config.topK = topK
                return DeepSearch(store: VectorStore.shared, config: config)
                    .retrieve(query: query)
            } else {
                let retriever = LocalRetriever(store: VectorStore.shared)
                return retriever.retrieve(query: query, k: topK, trace: false)
            }
        }.value
```

→ `LocalRetriever.retrieve` (`Shared/RAG/LocalRetriever.swift:33`) or `DeepSearch.retrieve` (`Shared/RAG/DeepSearch.swift:39`), both over `VectorStore.shared`.

**Hop 4 — generation.** `LocalExecutor.swift:126-130` (quoted in Section 2, row 1).

**Hop 5 — prompt + decode.** `LLMModel.generateAsync` → `runNoesisCompletion` (`NoesisCompletionPipeline.swift:88`) → `buildPrompt` (`NoesisCompletionPipeline.swift:62`).

### Is there a path that calls `generateAsync(context: "")`/`nil` *without* going through `LocalExecutor.execute`?

**Yes — two legacy paths exist**, both via `ModelManager.generateAsyncAnswer` (Section 2, row 2):

- `Shared/Execution/ExecutionCoordinator.swift:350-353` (`executeLocal` → `generateAsyncAnswer`). This is a **separate coordinator** from the canonical `HybridExecutionCoordinator`. Its own header comment (`ExecutionCoordinator.swift:273-277`) calls it *"this Preview-only coordinator … slated for removal in R4 (ADR-0008)."*
- `Shared/ContentView.swift:444` (`askRAG` → `generateAsyncAnswer`) — the shared/iOS-era `ContentView`, which calls `ModelManager` directly, bypassing **both** coordinators and `LocalExecutor`.

**However, neither produced the Q3 log.** Both bypass the `🧠 [SESSION-MEM/COORD]` and `🧠 [SESSION-MEM/EXEC]` prints entirely (those live only in `HybridExecutionCoordinator` and `LocalExecutor`). The Q3 log *contains* the COORD and EXEC lines, so Q3 went through `HybridExecutionCoordinator → LocalExecutor.execute(history-aware)`. The non-LocalExecutor paths are real and dangerous (they would silently drop history and emit no 🔎 trace), but they are **not** the path Q3 took.

Given the path through `LocalExecutor.execute` *is* the path Q3 took, and the `🔎` prints are still missing despite sitting unconditionally on it (Section 1), the remaining explanation is **not** an overload mismatch (ruled out in Section 1) — it is that the binary that produced the log did not contain PR #103. See Section 8.

---

## Section 4 — The `history.count` jump from 2 → 3

In the entire dispatch chain, **nothing appends the current turn to `history`.** Tracing the value:

- `DesktopChatView.swift:261` builds `history = SessionMemory.history(from: documentManager.qaHistory)` from prior turns only (the new pair is added later at `:271`).
- `SessionMemory.history(from:)` (`Shared/Execution/SessionMemory.swift:49-75`) caps at `maxTurns = 3` (`:33`) and **only drops** turns; it never adds.
- `HybridExecutionCoordinator.swift:199-203` passes `request.history` verbatim.
- `LocalExecutor.swift:126-130` passes `history` verbatim to `generateAsync`.
- `LLMModel.swift:88-94` passes `history` verbatim to `runNoesisCompletion`.
- `NoesisCompletionPipeline.swift:62` passes `history` verbatim to `buildPrompt`.

`buildPrompt` itself does not mutate it — it just iterates (`NoesisCompletionPipeline.swift:241`):

```swift
    var historyTurns = ""
    for turn in history {
```

A repo-wide grep for `history.append` / `history + […]` / `.appending` on the history value found **no mutation site** in the dispatch chain.

**Conclusion:** there is **no `+1` anywhere between COORD and `buildPrompt` in current source.** A single Q3 turn that logs `history.count=2` at COORD/EXEC must log `history.count=2` at `buildPrompt`. The current question is **not** appended to its own history before prompting (it is appended to the transcript *after* the response, `DesktopChatView.swift:271`).

Therefore the observed `2 → 3` is **not** an in-chain off-by-one. The two most likely benign explanations:

1. **Cross-turn log interleaving.** Q3 is the third question; before it the transcript holds 2 turns → `count=2`. After Q3 completes the transcript holds 3. The `buildPrompt … history.count=3` line in the pasted excerpt (which contains a `…` elision) most plausibly belongs to the **next** turn (Q4), whose prior transcript already held 3 turns.
2. **Stale/stitched binary** (same root as Section 1/8): the log was produced by a build whose threading differs from current `main`.

This cannot be disambiguated from static reading — it needs the full, timestamped, un-elided log (see Section 9).

---

## Section 5 — Where does `|>` residue come from?

**Prompt construction (the residue's *source* template).** `buildPrompt` emits **ChatML** — `<|im_start|>` / `<|im_end|>` (`NoesisCompletionPipeline.swift:241-261`):

```swift
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
```

This is fed to **Llama-3.2-3B-Instruct** (`LLMModel.swift:66`), whose chat template is Llama-3 (`<|begin_of_text|>`, `<|start_header_id|>…<|end_header_id|>`, `<|eot_id|>`) — **not** ChatML. The template mismatch makes the model echo/emit stray `<|…|>` fragments.

**Decode → string, in order:**

1. **Mid-stream loop** `NoesisCompletionPipeline.swift:137-171` — strips `<think>…</think>` and, on seeing `<|im_end|>`, keeps the prefix and stops (`:159-165`). It handles **only** `<think>` and `<|im_end|>`. It does **not** handle `<|eot_id|>`, `<|start_header_id|>`, `<|end_header_id|>`, or bare `|>`.
2. **`cleanOutput(_:)`** `NoesisCompletionPipeline.swift:269-296` — the step that *ought* to strip the markers:

```swift
    // Step 2: Remove broken fragments
    out = out.replacingOccurrences(of: "<\\|im(?:_[a-z]+)?", with: "", options: .regularExpression)
    out = out.replacingOccurrences(of: "</im[^>]*", with: "", options: .regularExpression)
    out = out.replacingOccurrences(of: "<im[^>]*", with: "", options: .regularExpression)
    …
    // Step 4: Remove any remaining tags
    out = out.replacingOccurrences(of: "<\\|im_start\\|>[^<]*", with: "", options: .regularExpression)
    out = out.replacingOccurrences(of: "<\\|im_end\\|>", with: "", options: .regularExpression)
```

3. **`extractFinalAnswer(_:)`** `NoesisCompletionPipeline.swift:298-330` — picks the longest paragraph; no tag stripping.

The returned `finalAnswer` becomes `ExecutionResult.output` → `NoemaResponse.text` → `QAPair.answer` (`DesktopChatView.swift:271-274`) → next turn's `history[i].answer` → re-emitted verbatim inside `historyTurns` (`NoesisCompletionPipeline.swift:247`). So any residue that survives `cleanOutput` **accumulates** across turns.

**Which fragments OUGHT to be stripped, and whether the code does it:**

| Fragment | Should strip? | Caught by current code? | Why / why not |
|----------|---------------|-------------------------|----------------|
| `<\|im_start\|>`, `<\|im_end\|>` (well-formed) | yes | **yes** | Step 4 regexes (`:291-292`) and step 2 (`:274`). |
| `<\|im…` partial (e.g. `<\|im_st`) | yes | **yes** | Step 2 `<\|im(?:_[a-z]+)?` (`:274`). |
| `<\|eot_id\|>` (Llama-3 native) | yes | **NO** | All step-2/step-4 regexes require the literal `im` after `<\|`. `<\|eot` never matches. Survives intact. |
| `<\|start_header_id\|>`, `<\|end_header_id\|>`, `<\|begin_of_text\|>` | yes | **NO** | Same reason — not the `im` family. |
| **bare `\|>`** (no leading `<`) | yes | **NO** | Every regex anchors on `<`. A standalone `\|>` (the exact residue Taka reports, and `\|>assistant`) matches none of them. |
| `<think>…</think>` | yes | yes | Step 1 (`:271`) + mid-stream loop. |

**Conclusion for Section 5:** stripping *does* exist, in `cleanOutput` (`NoesisCompletionPipeline.swift:269-296`), but it is scoped to the **ChatML `im` family** plus `<think>`. It has **no coverage** for (a) bare `|>` fragments lacking the `<|im` prefix and (b) Llama-3 native special tokens (`<|eot_id|>` etc.). Because the prompt template (ChatML) is mismatched to the model (Llama-3), the model emits exactly the fragments `cleanOutput` does not catch; they survive into `QAPair.answer` and are re-injected into every subsequent prompt via `historyTurns`. That is the `|>` / `|>assistant` accumulation.

(Would help, in a follow-up patch: switch `buildPrompt` to the Llama-3 chat template to match the model, and/or broaden `cleanOutput` to strip `<\|[a-z_]+\|>` generally and orphan `\|>` fragments. Noted only — not applied.)

---

## Section 6 — Will Q1 match Q3's path?

**Yes, Q1 takes the identical path and the same retrieval code.** There is **no per-question branching** in the dispatch chain:

- Routing in `HybridExecutionCoordinator.buildQuestion` (`:276-301`) keys off keyword heuristics for *tool/privacy/latency*, not topic; all of Q1–Q3 route `.local`.
- `LocalExecutor.execute` (`:70-149`) runs retrieval unconditionally; the only per-call difference is `defaultTopK` (5 on macOS) and `dynamicTopK` by query length (`LocalRetriever.swift:83-90`) — both questions are >50 chars, so both get the same effective `k`.

The deciding factor for `Context: none` is purely whether retrieval returned chunks. `LocalRetriever.retrieve` returns `[]` in exactly two cases:

`Shared/RAG/LocalRetriever.swift:43-47`:

```swift
        let allChunks = store.chunks
        guard !allChunks.isEmpty else {
            if trace { print("[Retriever] No chunks in VectorStore.") }
            return []
        }
```

and `Shared/RAG/LocalRetriever.swift:74`:

```swift
        if candidateList.isEmpty { return [] }
```

`LocalRetriever` applies **no min-score threshold** (unlike `BanditRetriever`, `BanditRetriever.swift:28-37`). Embedding retrieval (`store.retrieveChunks`, `:70`) returns top-k by cosine ordering regardless of score, so `candidateList` is non-empty whenever the store is non-empty. Therefore `Context: none` on the dispatched path overwhelmingly implies **`VectorStore.shared.chunks` was empty at query time** — which is a *global* condition, identical for Q1 and Q3.

**Prediction:** if Q3 hit `Context: none` because the store was empty, **Q1 also hit `Context: none`**, and Q1's correct-looking Spinoza quote was **Llama-3.2-3B general knowledge, not RAG.** There is no per-question condition that could have fed Q1 context while starving Q3. (This prediction is exactly what PR #103's `🔎 [LocalExecutor/RAG] store-state: … chunks.count=` line was built to confirm — and its absence from the log is itself the Section-8 finding.)

---

## Section 7 — `LLMModel.generateAsync` signature(s) and `context`

The sole async definition, `Shared/LLMModel.swift:51-55`:

```swift
    func generateAsync(
        prompt: String,
        context: String?,
        history: [ConversationTurn] = []
    ) async throws -> String {
```

- **`context` plumbing:** `context` is `String?` with **no default** (the caller must pass it, but may pass `nil`). It flows to `runNoesisCompletion(question:context:…)` (`LLMModel.swift:90`) → `buildPrompt(question:context:history:)` (`NoesisCompletionPipeline.swift:62`). In `buildPrompt` (`:234-238`) a `nil`/blank context triggers `⚠️ [buildPrompt] WARNING: No context provided`.
- **Default value:** `context` has none; `history` defaults to `[]` (the ADR-0009 additive parameter).
- **Optionality / overloads:** `context` is already `Optional` at the type level. Both async call sites pass `context.isEmpty ? nil : context` (`LocalExecutor.swift:128`, `ModelManager.swift:390`), so an empty join becomes `nil`. The sync wrappers `generate(prompt:)` → `generate(prompt:context:)` (`LLMModel.swift:27-45`) feed `nil`/their own context into the same async method. No overload makes `context` *non-optional*; no variant adds a non-nil default.

---

## Section 8 — Top 3 likely root causes, ranked

### #1 — The UAT binary did not include PR #103 (stale build / DerivedData)

**Hypothesis.** The log was produced by a build predating commit `8170f1f`, so the `🔎` prints simply weren't compiled in.

**Evidence.** Section 1: the three `🔎` blocks (`LocalExecutor.swift:81-114`) sit on a strictly linear path *between* the two `🧠 [SESSION-MEM/EXEC]` prints (`:76` and `:124`). Both `🧠` lines appear in the log; none of the `🔎` lines do. In any binary compiled from current `main`, executing line 76 and line 124 **forces** execution of 81–114 — there is no branch, return, or throw between them (Section 1). Section 1 also rules out the two competing mechanical explanations: the prints are **not** on the wrong overload (the called method #2 is the one with the prints, proven by the EXEC entry line), and there is **no protocol-extension dispatch shadowing** (the history-aware method is a witnessed requirement). Section 4 independently points the same way: the `2 → 3` history discrepancy also cannot arise from current source. Two unrelated "current source can't produce this log" findings converging is the signature of a stale artifact.

**Minimum diagnostic to confirm.** Clean DerivedData and rebuild (`Product ▸ Clean Build Folder`, delete `~/Library/Developer/Xcode/DerivedData/NoesisNoema-*`), then re-run Q3 and check whether `🔎 [LocalExecutor/RAG] store-state:` appears. If it now appears, root cause confirmed — no code change needed. (Pure verification step; no source edit.)

### #2 — `VectorStore.shared` is empty at query time (RAG never had data to retrieve)

**Hypothesis.** Independent of the print question, Q3 got `Context: none` because `VectorStore.shared.chunks` was empty when `LocalExecutor` retrieved.

**Evidence.** Section 6: `LocalRetriever.retrieve` returns `[]` only on an empty store (`LocalRetriever.swift:44-47`) or empty candidate set (`:74`); it has no score threshold, so a populated store essentially always yields candidates. `Context: none` therefore implies an empty store — a global condition that also explains why Q1's quote would be model-general-knowledge (Section 6). This is *orthogonal* to #1: even with PR #103's prints present, an empty store still yields `Context: none`. #1 explains the *missing trace*; #2 explains the *empty context*.

**Minimum diagnostic to confirm.** Read `VectorStore.shared.chunks.count` at the `LocalExecutor` boundary — which is precisely what `🔎 [LocalExecutor/RAG] store-state:` (`LocalExecutor.swift:81`) already prints. So a clean rebuild (#1's step) simultaneously confirms or refutes #2. If `chunks.count == 0`, investigate index load/ingestion timing (was the Spinoza corpus loaded into `VectorStore.shared` before the first question?).

### #3 — Prompt/template + cleanup mismatch corrupts history (secondary; explains `|>`, not `Context: none`)

**Hypothesis.** ChatML prompt against a Llama-3 model produces `<|…|>` / bare `|>` residue that `cleanOutput` doesn't strip; it accumulates in history and degrades later turns.

**Evidence.** Section 5: `buildPrompt` emits ChatML (`NoesisCompletionPipeline.swift:241-261`) but the model is Llama-3.2-3B-Instruct (`LLMModel.swift:66`); `cleanOutput` (`:269-296`) strips only the `im` family + `<think>`, leaving `<|eot_id|>` and bare `|>` untouched; residue round-trips through `QAPair.answer` into `historyTurns`. This is a real correctness defect but it does **not** cause `Context: none` — it is the most likely source of the `|>`/`|>assistant` leakage Taka reports, and a contributor to history bloat.

**Minimum fix to resolve (described, not written).** Align `buildPrompt` to the Llama-3 chat template so prompt and model agree, and/or broaden `cleanOutput` to strip a general `<\|[a-z_]+\|>` pattern plus orphan `\|>` fragments before the text is stored as an answer.

---

## Section 9 — Open questions (cannot answer from static reading)

1. **Was the UAT binary actually built from `8170f1f`?** Static reading proves the log is inconsistent with current source, but cannot prove which commit was compiled. Need: the build's commit hash / build timestamp, or a clean rebuild + re-run observing whether `LocalExecutor.swift:81` (`🔎 … store-state`) prints.
2. **What was `VectorStore.shared.chunks.count` at Q3 retrieval time?** Decisive for #2, but only observable at runtime. Need the runtime value at `LocalExecutor.swift:81`, or an equivalent trace of `VectorStore.shared.chunks.count` at dispatch.
3. **Is the `2 → 3` from cross-turn interleaving or a stitched/stale log?** Static reading shows no in-chain `+1` (Section 4). Need the full, un-elided, timestamped console log spanning Q3→Q4 to confirm the `buildPrompt … count=3` line belongs to the next turn rather than Q3.
4. **When is the Spinoza corpus loaded into `VectorStore.shared` relative to the first query?** Ingestion/index-load timing is not traceable from the dispatch files read here. Need a runtime trace of the load call vs the first `LocalExecutor.execute`, or a read of the VectorStore population path (out of scope for this dispatch-focused investigation).
5. **Are the two legacy non-LocalExecutor paths (`ExecutionCoordinator.executeLocal`, `ContentView.askRAG`) reachable in the shipped macOS app?** They exist (Section 3) and would silently drop history + emit no `🔎` trace, but I could not confirm from static reading whether any live macOS view instantiates `ExecutionCoordinator` or renders the shared `ContentView`. Need a usage/runtime confirmation that the macOS app only ever drives `HybridExecutionCoordinator` via `DesktopChatView`.
