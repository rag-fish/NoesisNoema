Title: Unstick first-token: migrate Swift wrapper to current llama.cpp batch/sampling APIs, enforce BOS/stop, detach generation, and add hard first-token watchdog + fallback

Context
- App: Noesis Noema (Swift-only, macOS focus for now). xcframeworks (llama_macos/ios) are prebuilt; do not rebuild here.
- After prior instrumentation, UI locks Ask properly but no tokens are ever streamed; it stays “querying…”. No crash.
- DONE summary shows watchdogs, but we still have no first token in real run.
- Likely causes:
	1.	Swift wrapper is using obsolete llama APIs (decode loop not driving in latest llama.cpp).
	2.	Missing BOS token or bad prompt packing for instruct models (no output).
	3.	Stop sequences or repeat-penalty mishandling stalling decoding.
	4.	Async deadlock: generation running on MainActor or blocked by UI thread.
	5.	Too-large model path selected (e.g., gpt-oss-20b-F16) → extremely slow; we must fallback fast.

Goals
- Ensure we reliably get the first generated token within a strict budget (e.g., ≤ 8s on Jan-v1-4B).
- Use current llama.cpp generation path: batch + sampler helpers.
- Enforce BOS + EOS + stop sequences; fix prompt template for instruct models.
- Run generation off the main thread (Task.detached), stream tokens back on MainActor, and always clear isGenerating.
- If no first token in time, abort and fallback automatically to Jan-v1-4B-Q4_K_M.gguf.

Tasks
	1.	Migrate wrapper to the current llama.cpp generation flow
In NoesisNoema/Shared/Llama/LibLlama.swift (or LlamaBridge.swift), refactor to match latest examples:
- Use llama_context, llama_batch_init, llama_tokenize, llama_decode, and the new sampling helpers (llama_sampler_* stack).
- Pseudocode outline (adjust to Swift bridging):

```ts
// tokenize with BOS
var toks = [llama_token](repeating: 0, count: N)
let addBos: Bool = true
let nPrompt = llama_tokenize(model, prompt, &toks, toks.count, addBos, /*special=*/true)

// eval prompt
var batch = llama_batch_init(nBatch, 0, 1)
// fill batch with prompt toks ...
llama_decode(ctx, batch)

// sampling stack
let smpl = llama_sampler_chain_init(ctx) // top_k, top_p, temp, repeat_penalty etc.

// generation loop
var firstTokenAt: TimeInterval? = nil
for step in 0..<maxNewTokens {
  let id = llama_sampler_sample(smpl, ctx, /*apply_penalties=*/true)
  if firstTokenAt == nil { firstTokenAt = now() }
  // append piece, stream to UI
  if id == EOS { break }
  // feed back the sampled token
  // prepare batch with single token & llama_decode
}
llama_sampler_free(smpl)
llama_batch_free(batch)
```

- Ensure n_threads > 0, n_batch sane (e.g., 256–1024), and context length from preset.
- Print llama_print_system_info() and meta (arch, vocab) once per load (DEBUG).

	2.	BOS/EOS & stop sequences
- Force BOS on tokenize for instruct models.
- Configure EOS and stop strings (e.g., </s>, ###, or preset-defined).
- Prevent stall from an empty decode by guarding: if llama_decode returns error → throw initFailed/decodeFailed.
- Add max-wall-time first-token watchdog (e.g., 8s for Jan-v1-4B): if no token by deadline → cancel generation and surface an inline error.
	3.	Prompt template sanity
- For instruct models, build prompt as:
```bash
[INST] <<SYS>>
{system}
<</SYS>>
{RAG_CONTEXT}
{USER_PROMPT}
[/INST]
```
or the model’s documented format.

- If RAG returns 0 chunks, proceed without context (don’t block).

	4.	Async isolation / UI streaming
- Run generation in Task.detached(priority: .userInitiated).
- Only do await MainActor.run { ... } to append streamed text & flip isGenerating = false.
- Use defer { Task { @MainActor in self.isGenerating = false } } to always unlock even on failure.
	5.	Fallback strategy
- If selected model fails to produce a first token under watchdog, log and auto-switch to Jan-v1-4B-Q4_K_M.gguf, then retry once.
- Surface a small banner:
“Primary model timed out (no first token). Fallback: Jan-v1-4B.”
	6.	Verbose diagnostics (DEBUG only)
- Print:
- 🧩 arch=..., vocab=..., n_ctx=..., n_threads=..., n_batch=...
- 🚀 first token at X.XXs (or timeout)
- 🏁 total tokens, wall time
- On error, bubble up a typed error; never silently hang.

Acceptance criteria
- With Jan-v1-4B-Q4_K_M.gguf selected, asking “1+1?” streams tokens within ≤ 8s first token on macOS.
- With an oversized/slow model (e.g., GPT-OSS-20B-F16), app times out first token and falls back to Jan-v1-4B automatically; user sees a clear banner; response arrives.
- isGenerating never stays true after completion/error.
- No infinite “querying…” state.
- iOS target compiles; the same wrapper change works (we’ll test next).

Do not
- Don’t rebuild xcframeworks or touch CMake. Swift layer only.
- Don’t introduce Core ML/tokenizer packages. Stay with gguf + llama.cpp wrapper.

Post-fix test steps
	1.	Select Jan-v1-4B → ask “1+1?” → expect streamed tokens; confirm 🚀 first token … log.
	2.	Select Gpt-Oss-20B-F16 → short prompt → expect timeout banner + auto-fallback → response streams via Jan-v1-4B.
	3.	Try with/without RAG context; both must return.
