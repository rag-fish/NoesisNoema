# NoesisNoema 🧠✨

[![GitHub release](https://img.shields.io/github/v/release/raskolnikoff/NoesisNoema)](https://github.com/raskolnikoff/NoesisNoema/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20iOS-blue)](#)
[![Swift](https://img.shields.io/badge/swift-5.9-orange)](#)

Private, offline, multi‑RAGpack LLM RAG for macOS and iOS.
Empower your own AGI — no cloud, no SaaS, just your device and your knowledge. 🚀

[![YouTube Demo](https://img.youtube.com/vi/VzCrfXZyfss/0.jpg)](https://youtube.com/shorts/VzCrfXZyfss?feature=share)

<img src="docs/assets/rag-main.png" alt="Main UI" height="400" />
<img src="docs/assets/noesisnoema_ios.png" alt="iOS UI" height="400" />

---

## What’s New in v0.3 (Dec 2025) 🔥

This release delivers the first fully unified and polished mobile + desktop experience.

### iOS (Major Overhaul)
- Full‑screen edge‑to‑edge layout (iPhone 17 Pro Max verified)
- New compact header with philosophical manuscript background (Husserl)
- Stable layout across light/dark mode
- Restored correct answer rendering (white‑on‑white bug fixed)
- RAG answers now load reliably on‑device using the unified pipeline
- History view correctly loads threads and supports per‑question detail

### macOS
- Parity refinements with the new iOS interface
- Improved consistency in RAG retrieval behavior

### Core RAG Engine
- Unified RAGpack v2 pipeline
- Cleaner answer normalization
- Reduced UI blocking during inference
- Pre‑flight guards around model loading and tokenizer workflows

### Stability
- Eliminated inconsistent safe‑area behavior across navigation wrappers
- Fixed residual navigation‑controller padding issues from older builds

---

## Performance Issues Identified (Dec 2025) ⚡

During the development of v0.3, several bottlenecks surfaced during real‑device testing on iPhone 17 Pro Max. These findings now drive our v0.4 optimization cycle.

1. Tokenizer execution performing work on the main thread
2. Repeated loading of embeddings, tokenizer vocab, and metadata
3. Non‑streaming generation resulting in synchronous UI stalls
4. RAGpack v2 `.zip` extraction missing an effective caching layer
5. Oversized default context window causing unnecessary compute
6. Swift Concurrency task switching overhead during retrieval

These are addressed under branch:
`feature/rag-perf-optimization-2025`.

## Optimization Plan (v0.3 → v0.4) 🚀

- Move tokenizer and embedding lookup off the MainActor
- Preload embeddings asynchronously at app startup
- Implement llama.cpp streaming callbacks to eliminate blocking
- Introduce aggressive caching layers for embeddings, tokenizer vocab, and RAGpack metadata
- Dynamically scale context window based on query type
- Add precise instrumentation for each phase (tokenize / retrieve / generate)
- Maintain API compatibility across macOS & iOS targets

These changes aim to deliver a smoother, significantly faster private‑RAG experience.

## Features ✨

- Multi‑RAGpack search and synthesis
- Transversal retrieval across packs (e.g., Kant × Spinoza)
- Deep Search (query iteration + MMR re‑ranking) with cross‑pack support
- Fast local inference via llama.cpp + GGUF models
- Private by design: fully offline; no analytics; minimal, local SystemLog (no PII)
- Feedback & learning: thumbs up/down feeds ParamBandit to auto‑tune retrieval (session‑scoped, offline)
- Modern UX
  - Two‑pane macOS UI
  - iOS (v0.3)
    - Stable full‑screen layout; compact header with manuscript background
    - Multiline input restored with proper dark/light mode rendering
    - Clear Ask / History / Settings tab design
    - QADetail overlays functioning with correct dismiss gestures
    - Reliable answer rendering with proper color handling
- Clean answers, consistently
  - `<think>…</think>` is filtered on the fly; control tokens removed; stop tokens respected
- Thin, future‑proof core
  - llama.cpp through prebuilt xcframeworks (macOS/iOS) with a thin Swift shim
  - Runtime guard + system info log for quick diagnosis

---

## Privacy & Diagnostics 🔒

- 100% offline by default. No network calls for inference or retrieval.
- No analytics SDKs. No telemetry is sent.
- SystemLog is local‑only and minimal (device/OS, model name, params, pack hits, latency, failure reasons). You can opt‑in to share diagnostics.

---

## Requirements ✅

- macOS 13+ (Apple Silicon recommended) or iOS 17+ (A15/Apple Silicon recommended)
- Prebuilt llama xcframeworks (included in this repo):
  - `llama_macos.xcframework`, `llama_ios.xcframework`
- Models in GGUF format
  - Default expected name: `Jan-v1-4B-Q4_K_M.gguf`

> Note (iOS): By default we run CPU fallback for broad device compatibility; real devices are recommended over the simulator for performance.

---

## Quick Start 🚀

### macOS (App)
1. Open the project in Xcode.
2. Select the `NoesisNoema` scheme and press Run.
3. Import your RAGpack(s) and start asking questions.

### iOS (App)
1. Select the `NoesisNoemaMobile` scheme.
2. Run on a real device (recommended).
3. Import RAGpack(s) from Files and Ask.
  - History stays visible; QADetail appears as an overlay (swipe down or ✖︎ to close).
  - Return adds a newline in the input; only the Ask button starts inference.

### CLI harness (LlamaBridgeTest) 🧪
A tiny runner to verify local inference.
- Build the `LlamaBridgeTest` scheme and run with `-p "your prompt"`.
- Uses the same output cleaning to remove `<think>…</think>`.

---

## Using RAGpacks 📦

RAGpack is a `.zip` with at least:

- `chunks.json` — ordered list of text chunks
- `embeddings.csv` — embedding vectors aligned by row
- `metadata.json` — optional, bag of properties

Importer safeguards:
- Validates presence of `chunks.json` and `embeddings.csv` and enforces 1:1 count
- De‑duplicates identical chunk+embedding pairs across packs
- Merges new, unique chunks into the in‑memory vector store

> Tip: Generate RAGpacks with the companion pipeline:
> [noesisnoema-pipeline](https://github.com/raskolnikoff/noesisnoema-pipeline)

---

## Model & Inference 🧩

- NoesisNoema links llama.cpp via prebuilt xcframeworks. You shouldn’t manually embed `llama.framework`; link the xcframework and let Xcode process it.
- Model lookup order (CLI/app): CWD → executable dir → app bundle → `Resources/Models/` → `NoesisNoema/Resources/Models/` → `~/Downloads/`
- Output pipeline:
  - Jan/Qwen‑style prompt where applicable
  - Streaming‑time `<think>` filtering and `<|im_end|>` early‑stop
  - Final normalization to erase residual control tokens and self‑labels

### Device‑optimal presets ⚙️

- A17/M‑series: `n_threads = 6–8`, `n_gpu_layers = 999`
- A15–A16: `n_threads = 4–6`, `n_gpu_layers = 40–80`
- Generation length: `max_tokens` 128–256 (short answers), 400–600 (summaries)
- Temperature: 0.2–0.4, Top‑K: 40–80 for stability

> These are sensible defaults; you can tune per device/pack.

---

## UX Details that Matter 💅

- iOS v0.3
  - Full‑screen, stable layout using updated HostingController stack
  - Correct rendering across dark/light modes
  - Persistent History tab with selectable past threads
  - Clean answer display with scroll indicators
  - Manuscript‑style header background with automatic scaling
- macOS
  - Two‑pane layout with History and Detail; same output cleaning; quick import

---

## Engineering Policy & Vendor Guardrails 🛡️

- Vendor code (llama.cpp) is not modified. xcframeworks are prebuilt and checked in.
- Thin shim only: adapt upstream C API in `LibLlama.swift` / `LlamaState.swift`. Other files must not call `llama_*` directly.
- Runtime check: verify `llama.framework` load + symbol presence on startup and log `llama_print_system_info()`.
- If upstream bumps break builds, fix the shim layer and add a unit test before merging.

---

## QA Checklist (release‑ready) ✅

- Accuracy: run same question ×3; verify gist stability at low temperature (0.2–0.4)
- Latency: measure p50/p90 for short/long prompts and multi‑pack queries; split warm vs warm+1
- Memory/Thermals: 10‑question loop; consider thread scaling when throttled
- Failure modes: empty/huge/broken packs; missing model path; user‑facing messages
- Output hygiene: ensure `<think>`/control tokens are absent; newlines preserved
- History durability: ~100 items; startup time and scroll smoothness
- Battery: 15‑minute session; confirm best params per device
- Privacy: verify network off; no analytics; README/UI clearly state offline

---

## Troubleshooting 🛠️

- `dyld: Library not loaded: @rpath/llama.framework`
  - Clean build folder and DerivedData
  - Link the xcframework only (no manual embed)
  - Ensure Runpath Search Paths include `@executable_path`, `@loader_path`, `@rpath`
- Multiple commands produce `llama.framework`
  - Remove manual “Embed Frameworks/Copy Files” for the framework; rely on the xcframework
- Model not found
  - Place the model in one of the searched locations or pass an absolute path (CLI)
- iOS keyboard won’t hide
  - Tap outside the input or scroll History to dismiss
- Output includes control tags or `<think>`
  - Ensure you’re on the latest build; the streaming filter + final normalizer should keep answers clean

---

## Known Issues & FAQ ❓

- iOS Simulator is slower and may not reflect real thermals. Prefer running on device.
- Very large RAGpacks can increase memory usage. Prefer chunking and MMR re‑ranking.
- If you still see `<think>` in answers, capture logs and open an issue (model‑specific templates can slip through).
- Where is `scripts/build_xcframework.sh`?
  - Not included yet. Prebuilt `llama_*.xcframework` are provided in this repo. If you need to rebuild, use upstream llama.cpp build instructions and replace the frameworks under `Frameworks/`.

---

## Roadmap 🗺️

- iOS universal polishing (iPad layouts, sharing/export)
- Enhanced right pane: chunk/source/document previews
- Power/thermal controls (device‑aware throttling)
- Cloudless peer‑to‑peer sync
- Plugin/API extensibility
- CI for App targets

---

## Ecosystem & Related Projects 🌍

- [RAGfish](https://github.com/raskolnikoff/RAGfish): Core RAGpack specification and toolkit 📚
- [noesisnoema-pipeline](https://github.com/raskolnikoff/noesisnoema-pipeline): Generate your own RAGpacks from PDF/text 💡

---

## Contributing 🤗

We welcome Designers, Swift/AI/UX developers, and documentation writers.
Open an issue or PR, or join our discussions. See also [RAGfish](https://github.com/raskolnikoff/RAGfish) for the pack spec.

PR Checklist (policy):
- [ ] llama.cpp vendor frameworks unchanged
- [ ] Changes limited to `LibLlama.swift` / `LlamaState.swift` for core llama integration
- [ ] Smoke/Golden/RAG tests passed locally

---

## From the Maintainers 💬

This project is not just code — it’s our exploration of private AGI, blending philosophy and engineering.
Each commit is a step toward tools that respect autonomy, curiosity, and the joy of building.
Stay curious, and contribute if it resonates with you.

🌟
> Your knowledge. Your device. Your rules.

---
## ParamBandit: Thompson Sampling to Select Optimal Parameters per Query 🔬

- What: A lightweight bandit that dynamically selects retrieval parameters (top_k, mmr_lambda, min_score) per query cluster.
- Why: Quickly improves relevance with minimal feedback and provides the feeling of a system that is learning.
- Where: Just before the generator, immediately before the retrieval pipeline.
- How:
  - Maintains Beta(α,β) distributions for each arm (parameter set) and selects using Thompson Sampling.
  - Updates α/β based on feedback events (👍/👎) from the RewardBus.
  - Example default arms: k4/l0.7/s0.20, k5/l0.9/s0.10, k6/l0.7/s0.15, k8/l0.5/s0.15.

Usage example (integration concept)
- Call ParamBandit just before existing LocalRetriever usage points, and perform retrieval with the returned parameters.
- On the UI side, trigger RewardBus.shared.publish(qaId:verdict:tags:) upon user feedback (👍/👎).

Simplified flow:
1) let qa = UUID()
2) let choice = ParamBandit.default.chooseParams(for: query, qaId: qa)
3) let ps = choice.arm.params // topK, mmrLambda, minScore
4) let chunks = LocalRetriever(store: .shared).retrieve(query: query, k: ps.topK, lambda: ps.mmrLambda)
5) Filter by minScore for similarity (see BanditRetriever)
6) On user evaluation, call RewardBus.shared.publish(qaId: qa, verdict: .up/.down, tags: …)

Tests and Definition of Done (DoD)
- Unit: Verify initial α=1, β=1, and that 👍 increments α and 👎 increments β (add to TestRunner, skip in CLI build).
- Integration: Confirm preference converges to the best arm with composite rewards (same as above).
- DoD: Add ParamBandit as an independent service, integrate with RewardBus, define default arms, and provide lightweight documentation (this section).
