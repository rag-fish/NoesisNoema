# Audit: Multi-turn context-overflow on retrieval

- **Date:** 2026-06-16
- **Type:** READ-ONLY root-cause audit (diagnose, do **not** fix)
- **Trigger (iPhone device UAT):**
  - Single-turn (cleared history) "Define conatus" → ✅ correct RAG answer.
  - Same question asked as the **4th turn** of a conversation → ❌
    *"The question exceeded the model's context window. Try a shorter question
    or clear chat history."*
- **Hypothesis (confirmed):** the RAG prompt + a single question fits `n_ctx`;
  the RAG prompt + accumulated chat history overflows. Device `n_ctx` is fine;
  **unbounded history token volume** is the swing variable.

---

## 1. Executive verdict

The overflow is **not** a device-`n_ctx` problem and **not** the PR #111
stop-condition bug. It is an **unbudgeted prompt-assembly** problem:

1. Chat history is admitted into the prompt with a **count/time cap only**
   (≤ 3 turns within 45 min) — there is **no token-level cap**. Each prior
   turn carries its full question **and** full answer verbatim, and answers can
   each be up to `n_len` (256 tokens on iOS).
2. The RAG-context truncation in `LocalExecutor` is computed **blind to
   history** — it reserves a fixed 200-token slack for "system + question" and
   lets retrieved context fill the rest of `n_ctx`. It never reserves budget
   for the history that `buildPrompt` will prepend.
3. The two are assembled in different layers that never share a token budget,
   so once history is non-trivial the combined prompt trips the **pre-decode
   KV-budget tripwire** (`kvBudgetExceeds`, added by the #111-era Fix B1). The
   tripwire works correctly and fails *cleanly before decode* — but it
   **rejects the whole request instead of trimming history to fit**, which is
   what the user experiences as the error.

**The budget *check* exists and is correct. What is missing is budget-aware
*trimming* on the prompt-assembly path.** PR #111's fix does **not** cover this.

---

## 2. The exact device call chain

iOS app target = `Apps/iOS/NoesisNoemaMobile/`.

| Step | File:line | What happens |
|------|-----------|--------------|
| App entry | `Apps/iOS/NoesisNoemaMobile/NoesisNoemaMobileApp.swift:19,24` | builds `HybridExecutionCoordinator`, renders `RootView` |
| Chat tab (tab 0) | `Apps/iOS/NoesisNoemaMobile/Views/TabRootView.swift:30-37` | `default:` case renders `MobileHomeView` (the chat screen) |
| History derived | `Apps/iOS/NoesisNoemaMobile/Views/MobileHomeView.swift:318` | `SessionMemory.history(from: documentManager.qaHistory)` — applies ≤3-turn / 45-min caps |
| Request built | `MobileHomeView.swift:329-330` | `NoemaRequest(query: trimmed, history: history)` |
| Coordinator | `Shared/Runtime/Execution/HybridExecutionCoordinator.swift:202` | dispatches `history: request.history` to executor |
| Executor | `Shared/Runtime/Executors/LocalExecutor.swift:70-150` | retrieves chunks, truncates context, calls `generateAsync(history:)` |
| LLM shim | `Shared/LLMModel.swift:88-94` | `runNoesisCompletion(..., history: history)` |
| Prompt build | `Shared/Llama/NoesisCompletionPipeline.swift:62, 225-262` | `buildPrompt(question:context:history:)` |
| KV tripwire | `Shared/Llama/LibLlama.swift:259-264` | `kvBudgetExceeds` → bail before decode |
| Error string | `Shared/Llama/NoesisCompletionPipeline.swift:92-98` | returns the user-facing "exceeded context window" message |

> **Note — a second, divergent path exists.** `ContentView.askRAG`
> (`Shared/ContentView.swift:444`) calls `ModelManager.generateAsyncAnswer`
> (`Shared/ModelManager.swift:279-419`), which passes **no history**
> (`ModelManager.swift:390`) and applies **no context truncation**
> (`ModelManager.swift:353`). That path would *not* reproduce this bug (no
> history) but is a latent inconsistency. The shipping iOS device uses the
> `MobileHomeView` → coordinator path above, which is history-aware.

---

## 3. Prompt assembly — components and order

`Shared/Llama/NoesisCompletionPipeline.swift:225-262` (`buildPrompt`).

Concatenation order (lines 253-256):

```swift
let prompt = "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(sys)<|eot_id|>"
    + historyTurns                                                              // prior turns
    + "<|start_header_id|>user<|end_header_id|>\n\n\(user)<|eot_id|>"           // current Q + RAG ctx
    + "<|start_header_id|>assistant<|end_header_id|>\n\n"                        // generation primer
```

1. **System prompt** (lines 233-237) — fixed ~3-line RAG instruction, once at top.
2. **History turns** (lines 247-251) — for each prior turn, a user header
   (prior question) **and** an assistant header (prior answer), both verbatim,
   chronological. **RAG context is *not* attached to history turns.**
3. **Current user turn** (lines 238-240) — `"Question: <q>"` then, if context
   present, `"\n\nContext:\n<ctx>"`. **The retrieved RAG context is attached to
   the current turn only.**
4. **Assistant primer** (line 256) — empty, awaiting generation.

So the final order is: **system → chat_history → (current question + RAG context) → assistant**.

---

## 4. Chat history handling

- **Is history in the generation prompt?** Yes — on the device path
  (`MobileHomeView` → coordinator). Prepended between system and current turn.
- **How many prior turns?** Up to **3** (`SessionMemory.defaultMaxTurns = 3`,
  `Shared/Execution/SessionMemory.swift:33`), additionally filtered to a
  **45-minute** window (`defaultWindow = 45*60`, line 29).
- **Source of history.** The user-visible transcript
  `DocumentManager.qaHistory: [QAPair]` (`Shared/DocumentManager.swift:69`),
  mapped to `[ConversationTurn]` by `SessionMemory.history(from:)`
  (`SessionMemory.swift:49-75`). Per ADR-0009 / ADR-0000 §4 there is no hidden
  store — history is strictly the visible transcript.
- **Is the full transcript replayed each turn?** Each admitted turn is replayed
  **in full** — both question and answer text, verbatim (`buildPrompt`
  `NoesisCompletionPipeline.swift:248-251`). The *number* of turns is capped at
  3; the *token volume per turn is not capped at all*.
- **Is there any trimming / sliding window today?** Only a **count + time**
  window (`SessionMemory.swift:55-67`):

  ```swift
  let recent = Array(inWindow.suffix(maxTurns))   // keep newest 3 in-window turns
  ```

  There is **no token-based trim** anywhere on the history path.

---

## 5. Context-budget accounting

### Effective values on the iOS device

| Quantity | Value (iOS device) | Source |
|----------|--------------------|--------|
| `n_ctx` | **1024** | `Shared/Llama/LibLlama.swift:131` (`#if os(iOS) ctx_params.n_ctx = 1024`) |
| `n_ctx` (macOS) | 4096 | `LibLlama.swift:133` |
| `n_batch` | = `n_ctx` (1024) | `LibLlama.swift:141` |
| `n_len` (effective) | **256** | `Shared/LLMModel.swift:173` (`balanced`/`auto` iOS → `nLen: 256`); set via `set_n_len(params.nLen)` at `NoesisCompletionPipeline.swift:82` |
| `n_len` (creative preset, iOS) | 384 | `LLMModel.swift:175` |
| Prompt token budget | **768** = 1024 − 256 | derived |

> **ADR-0010 caveat.** The "4096" figure applies **only to macOS**
> (`LibLlama.swift:133`). On the iOS device build `n_ctx = 1024`
> (`LibLlama.swift:131`). Any reasoning that assumed 4096 on device is wrong by
> 4×. The iOS `LlamaContext` is also constructed with `initialNLen: 256`
> (`LibLlama.swift:152`), but that initial value is **overridden** at runtime by
> `set_n_len(params.nLen)` (`NoesisCompletionPipeline.swift:82`) — for the iOS
> `balanced`/`auto` preset `params.nLen` is also 256, so the effective generation
> reserve is **256 tokens**.

### Is there a pre-generation token-budget check?

Yes — a **last-resort tripwire**, in `completion_init` **before** the decode
loop (`Shared/Llama/LibLlama.swift:249-264`):

```swift
let n_ctx     = Int(llama_n_ctx(context))   // 1024 on device
let n_prompt  = tokens_list.count
let n_kv_req  = n_prompt + Int(n_len)        // prompt + 256
...
if LlamaContext.kvBudgetExceeds(nPrompt: n_prompt, nLen: Int(n_len), nCtx: n_ctx) {
    last_error = "prompt + n_len (\(n_kv_req)) exceeds n_ctx (\(n_ctx))"
    is_done = true
    return false        // bail BEFORE any llama_decode
}
```

with the predicate (`LibLlama.swift:221-223`):

```swift
static func kvBudgetExceeds(nPrompt: Int, nLen: Int, nCtx: Int) -> Bool {
    return nPrompt + nLen > nCtx
}
```

When it bails, the pipeline maps `false` → the user-facing message
(`NoesisCompletionPipeline.swift:92-98`):

```swift
if !initOK {
    ...
    return "The question exceeded the model's context window. " +
           "Try a shorter question or clear chat history."
}
```

**It fails cleanly pre-decode — it does NOT fail mid-decode.** This is exactly
the Fix B1 guard from the #111 era. But it is a **tripwire, not a budget
manager**: it rejects the entire request rather than shedding history to fit.

### Relationship to PR #111

PR #111 fixed a **stop-condition** bug (`n_decode` vs `n_cur`) *inside* the
generation loop. The `kvBudgetExceeds` pre-check (Fix B1 / hotfix #4) is what
catches over-budget prompts *before* the loop. **This audit's issue is upstream
of both**: the prompt-assembly path admits unbounded history with no token
budgeting, so it trips the (correctly-working) tripwire. #111's fix does not
address prompt assembly — **confirmed distinct**.

---

## 6. RAG context size & truncation

- **Chunks retrieved (iOS):** `topK = 3` (`LocalExecutor.swift:42-43`), further
  reduced for short queries by `dynamicTopK` (`LocalRetriever.swift:87-94`):
  a 14-char query like "Define conatus" (< 20 chars) → `min(k, 2) = 2` chunks.
- **Injection:** chunks joined with `\n\n` (`LocalExecutor.swift:112`).
- **Truncation (the blind spot):** `LocalExecutor.swift:120-132`:

  ```swift
  #if os(iOS)
  let nCtx = 1024, nLen = 256
  #else
  let nCtx = 4096, nLen = 1024
  #endif
  let contextCharCap = max(0, (nCtx - nLen - 200)) * 3   // iOS: (1024-256-200)*3 = 1704 chars
  if joinedContext.count > contextCharCap {
      context = String(joinedContext.prefix(contextCharCap))
  }
  ```

  On iOS the RAG context is capped at **1704 chars ≈ 426–568 tokens**. The
  fixed `- 200` slack is the *only* reservation for everything else (system +
  question), and it **reserves nothing for history**. So retrieved context is
  allowed to consume essentially the whole prompt budget, leaving no room for
  the history that `buildPrompt` will prepend.

---

## 7. The overflow point (token math, iOS device)

Budget: prompt ≤ `n_ctx − n_len` = `1024 − 256` = **768 tokens** (≈ 4 chars/token).

| Component | Tokens (typical) | Bounded? |
|-----------|------------------|----------|
| System prompt + template scaffolding | ~50 | fixed |
| Current question ("Define conatus") | ~5 | user-set |
| Current-turn RAG context | ~150–568 (cap ≈ 568) | **capped, but blind to history** |
| Assistant primer | ~5 | fixed |
| **Single-turn subtotal** | **~210–630** | fits 768 ✅ |
| Each prior turn (Q + full answer + 2 headers) | **~110–290** | **UNBOUNDED** (answer ≤ `n_len`=256) |

**Single-turn** "Define conatus": ~210–280 tokens (2 short chunks) + 256
generation = well under 1024 → ✅ (matches UAT success).

**Adding history** (not counted by the LocalExecutor cap): headroom after the
single-turn baseline is `768 − ~280 ≈ 488` tokens for *all* history.

- 1 prior turn (~150–290) → still fits.
- 2 prior turns (~300–580) → near/at the edge.
- **3 prior turns (~330–870)** → exceeds the ~488 headroom whenever prior
  answers were substantial → `n_prompt + 256 > 1024` → **bail at the 4th
  question.** ✅ matches the observed UAT failure at turn 4.

If RAG context for a turn lands near its 568-token cap, headroom collapses to
~130 tokens and **even one** prior turn can overflow (as early as the 2nd
question). The exact overflow turn is data-dependent (RAG size × answer
lengths), but the trend is monotonic: every turn adds 110–290 tokens until the
3-turn plateau, and the plateau already exceeds budget for non-trivial answers.

**Swing variable:** cumulative **chat-history token volume**.
**Unbounded components:**
1. **History token volume** — turn *count* is capped (≤3) and time-windowed
   (45 min), but the *tokens per turn are uncapped*: each prior answer can be up
   to `n_len` (256 tokens) and each prior question is arbitrary length.
2. **The absence of a combined budget** — `LocalExecutor`'s RAG cap and
   `buildPrompt`'s history injection live in different layers and never share a
   token budget. RAG can legitimately fill to ~768; any history then overflows.

(RAG context itself *is* capped — that part is bounded — but the cap does not
co-budget with history, which is the actual defect.)

---

## 8. Recommendation (NOT implemented)

**Yes — the right shape is a token-budget trim that keeps RAG context + reserves
generation (`n_len`), and trims HISTORY (oldest-first) to fit.** This matches
the system's own priority order: retrieval quality and a complete answer matter
more than replaying old turns.

Minimal, single-accounting-point fix:

1. At **one** place that knows all four of `n_ctx`, `n_len`, the (already
   truncated) RAG context, and the current question — i.e. the pipeline
   (`runNoesisCompletion`/`buildPrompt`) or `LocalExecutor` — compute the fixed
   cost: `system + current_question + RAG_context + n_len + template`.
2. Admit history turns **newest-first**, summing their token cost, and **drop
   the oldest** turns until the remainder fits `n_ctx`. (Optionally drop a
   turn's *answer* before dropping the whole turn.)
3. Replace the count-only cap in `SessionMemory` with — or layer beneath it — a
   **token-budget** cap. Note `SessionMemory` alone *cannot* do this correctly
   because it does not know the RAG context size; the trim must run where the
   context is known. The 3-turn/45-min cap can remain as an outer bound.

Why not the alternatives:
- *Raise iOS `n_ctx` to 4096* — increases KV memory and latency on-device 4×;
  treats the symptom, and history would still be unbounded, just deferred.
- *Shrink `n_len`* — steals from answer quality; doesn't bound history.
- *Trim RAG instead of history* — inverts the priority; degrades the answer the
  user actually asked for to preserve old turns.

Keep the `kvBudgetExceeds` tripwire as the final safety net — but it should
rarely fire once the assembly path budgets history.

**Secondary (note, not in scope):** reconcile the two generation paths
(`ModelManager.generateAsyncAnswer` vs the coordinator path). Putting the
token-budget trim in the **shared pipeline** (`runNoesisCompletion`) makes both
paths benefit and prevents future drift.

---

## Appendix — files referenced

- `Shared/Llama/NoesisCompletionPipeline.swift` — pipeline, `buildPrompt`, error string, presets
- `Shared/Llama/LibLlama.swift` — `n_ctx`/`n_len`, `kvBudgetExceeds`, `completion_init`
- `Shared/LLMModel.swift` — `generateAsync`, `buildRuntimeParams` (effective `n_len`)
- `Shared/ModelManager.swift` — divergent `generateAsyncAnswer` path
- `Shared/Runtime/Executors/LocalExecutor.swift` — retrieval, RAG char-cap truncation
- `Shared/Execution/SessionMemory.swift` — ≤3-turn / 45-min history cap
- `Shared/Execution/ExecutionCoordinator.swift` — `NoemaRequest`, `ConversationTurn`
- `Apps/iOS/NoesisNoemaMobile/Views/MobileHomeView.swift` — device chat ask path
- `Apps/iOS/NoesisNoemaMobile/Views/TabRootView.swift` — chat tab wiring
</content>
</invoke>
