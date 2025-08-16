# NoesisNoema 🧠✨

Private, offline, multi‑RAGpack LLM RAG for macOS and iOS. 
Empower your own AGI — no cloud, no SaaS, just your device and your knowledge. 🚀

[![YouTube Demo](https://img.youtube.com/vi/VzCrfXZyfss/0.jpg)](https://youtube.com/shorts/VzCrfXZyfss?feature=share)

![Main UI](docs/assets/rag-main.png)
![iOS UI](docs/assets/noesisnoema_ios.png)

---

## What’s New (Aug 2025) 🔥

The on‑device experience leveled up across macOS and iOS:

- iOS Universal App (WIP → usable today)
  - Fresh iOS screenshot available in `docs/assets/noesisnoema_ios.png` (see above)
  - Always‑visible History, QADetail overlays on top (swipe‑down or ✖︎ to close)
  - Multiline input with placeholder, larger tap targets, equal‑width action buttons
  - Global loading lock to prevent duplicate queries; answer only appended once
  - Keyboard UX: tap outside or scroll to dismiss
- Output hygiene & stability
  - Streaming filter removes `<think>…</think>` and control tokens; stop at `<|im_end|>`
  - Final normalization unifies model differences for clean, copy‑ready answers
  - Runtime guard detects broken llama.framework loads; lightweight SystemLog
- RAGpack import is stricter and safer
  - Validates presence of `chunks.json` and `embeddings.csv` and enforces count match
  - De‑duplicates identical chunks across multiple RAGpacks

macOS keeps its “workstation feel”; iOS now brings the same private RAG, in your pocket. 📱💻

---

## Features ✨

- Multi‑RAGpack search and synthesis
- Transversal retrieval across packs (e.g., Kant × Spinoza)
- Fast local inference via llama.cpp + GGUF models
- Private by design: fully offline; no analytics; minimal, local SystemLog (no PII)
- Modern UX
  - Two‑pane macOS UI
  - iOS: History always visible; QADetail overlays; copy‑able answers; smooth keyboard handling
  - Multiline question input; equal‑width Ask / Choose RAGpack buttons
- Clean answers, consistently
  - `<think>…</think>` is filtered on the fly; control tokens removed; stop tokens respected
- Thin, future‑proof core
  - llama.cpp through prebuilt xcframeworks (macOS/iOS) with a thin Swift shim
  - Runtime guard + system info log for quick diagnosis

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

---

## UX Details that Matter 💅

- iOS
  - Interface preview: see screenshot [noesisnoema_ios.png](docs/assets/noesisnoema_ios.png)
  - Multiline input with placeholder; Return adds a newline (does not send)
  - Only the Ask button can start inference (no accidental double sends)
  - During generation: global overlay lock; all inputs disabled (no duplicate queries)
  - Tap outside or scroll to dismiss the keyboard
  - QADetail overlays History; close with swipe‑down or ✖︎; answers are text‑selectable and copyable
- macOS
  - Two‑pane layout with History and Detail; same output cleaning; quick import

---

## Ecosystem & Related Projects 🌍

- [RAGfish](https://github.com/raskolnikoff/RAGfish): Core RAGpack specification and toolkit 📚
- [noesisnoema-pipeline](https://github.com/raskolnikoff/noesisnoema-pipeline): Generate your own RAGpacks from PDF/text 💡

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

## Roadmap 🗺️

- iOS universal polishing (iPad layouts, sharing/export)
- Enhanced right pane: chunk/source/document previews
- Device‑optimal presets and power/thermal controls
- Cloudless peer‑to‑peer sync
- Plugin/API extensibility
- CI for App targets

---

## Contributing 🤗

We welcome Designers, Swift/AI/UX developers, and documentation writers.
Open an issue or PR, or join our discussions. See also [RAGfish](https://github.com/raskolnikoff/RAGfish) for the pack spec.

---

## From the Maintainers 💬

This project is not just code — it’s our exploration of private AGI, blending philosophy and engineering.  
Each commit is a step toward tools that respect autonomy, curiosity, and the joy of building.  
Stay curious, and contribute if it resonates with you.

🌟
> Your knowledge. Your device. Your rules.
