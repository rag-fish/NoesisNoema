Title: Make llama.cpp inference robust: log every stage, fail fast on init, validate GGUF arch, and stream tokens (macOS/iOS)

Context
- App: Noesis Noema (Swift-only), llama.cpp via xcframeworks (prebuilt outside Xcode).
- Models registered in app bundle Resources:
- Jan-v1-4B-Q4_K_M.gguf
- Llama-3.3-70B-Instruct-UD-IQ1_S.gguf
- gpt-oss-20b-F16.gguf
- Logs show:
- RAG returns 0 chunks (that’s fine for now)
- Selected model: Gpt Oss 20B F16
- Found model file at: .../gpt-oss-20b-F16.gguf
- No further logs (no “model loaded”, no “generation started”, no tokens)

Hypothesis
We’re hanging or returning early during model load / context creation / batch loop. Also, architecture mismatch (e.g., general.architecture) could make llama.cpp silently fail if we don’t surface the error.

Goals
	1.	Instrument LlamaBridge (or equivalent Swift wrapper) with granular logging and hard guards for every native call.
	2.	Validate GGUF architecture & vocab type before starting generation; print them.
	3.	Ensure we actually create context, prepare prompt (with or without RAG), run decode loop, and stream tokens back to UI.
	4.	Add timeout / watchdog to avoid dead awaits; always clear isGenerating.

Concrete tasks
- In the Swift wrapper around llama.cpp (e.g. LibLlama.swift / LlamaBridge.swift), add verbose logs (DEBUG only):

```ts
print("🧩 GGUF path: \(path)")
// After llama_model_loader
print("📦 GGUF meta: arch=\(arch), vocab=\(vocab), n_ctx=\(nCtx), n_gpu_layers=\(nGpu)")
// After llama_init
print("✅ llama_init done (ctx=\(ctx != nil))")
// Before eval
print("🚀 start generation: promptTokens=\(promptTokens.count)")
// During stream
print("🔹 token: \(piece)")
// On done
print("🏁 generation finished (tokens=\(count))")
```

- Fail fast on any null / error return:
- If model/context creation fails → throw LlamaError.initFailed(reason: ...)
- If tokenizer prep fails → throw LlamaError.tokenizeFailed
- If generation loop yields 0 tokens in N steps → throw LlamaError.noResponse
- Read GGUF metadata (via llama.cpp APIs if exposed, else at least print llama_model_desc() or similar) and log:
- general.architecture
- tokenizer.ggml / vocab type
- Reject unsupported arch with a friendly error:
“Model arch ‘X’ is unsupported by this build. Try Jan-v1-4B or a Llama-3-family quant.”
- Sampler & loop sanity
- Ensure we set sane defaults per preset (temp/top_p/top_k/repeat_penalty).
- Make sure we actually run a decode loop (llama_decode / batch API) and append generated tokens.
- Respect EOS (stop tokens, newline stop sequences).
- Put a max token cap and a time watchdog (e.g., 30s) to prevent infinite hang.
- Select smaller model for sanity
- If selected model is gpt-oss-20b-F16, also try jan-v1-4b automatically on failure, and log:
“Primary model failed to generate, falling back to Jan-v1-4B for diagnostics.”
- UI flow
- Always reset isGenerating = false on all code paths (defer).
- Stream tokens to MainActor each step. If no tokens after N ms, render an inline error.

Acceptance criteria
- Logs show:
- GGUF path + arch + vocab + ctx created
- “start generation …” then streamed tokens or explicit noResponse error.
- Asking a simple prompt with Jan-v1-4B returns tokens on macOS & iOS.
- If a model is unsupported or fails, user gets a clear inline message (not a silent hang).
- isGenerating never stays true after an error.
- No change to xcframework build process; we only fix Swift wrapper + model invocation.

Do not
- Don’t rebuild xcframeworks from Xcode.
- Don’t introduce CoreML / tokenizer packages. GGUF + llama.cpp only.

After changes
- Build macOS/iOS; in macOS run:
- Model: Jan-v1-4B → ask “1+1?” → confirm streamed tokens.
- Model: gpt-oss-20b-F16 → ask short prompt; if fails, see a readable error and fallback path logs.
