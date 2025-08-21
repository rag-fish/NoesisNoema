# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0] - 2025-08-16
### Added
- **Initial public release** of Noesis Noema 🎉
- macOS and iOS support with unified RAG experience
- Multi-RAGpack search and transversal retrieval (e.g., Kant × Spinoza)
- Companion CLI (`LlamaBridgeTest`) to validate inference
- Prebuilt `llama_macos.xcframework` and `llama_ios.xcframework` integration
- Streaming filter for `<think>…</think>` and `<|im_end|>` stop handling
- Output normalization for clean, copy-ready answers
- Importer safeguards:
  - Validates presence of `chunks.json` and `embeddings.csv`
  - Enforces 1:1 alignment between chunks and embeddings
  - Deduplicates identical pairs across packs
- UX improvements:
  - macOS: workstation-style two-pane UI
  - iOS: always-visible history, swipe-down closable detail overlays, multiline input, global lock during generation
- Added screenshots in `docs/assets/` for macOS and iOS UI
- Linked ecosystem projects:
  - [RAGfish](https://github.com/raskolnikoff/RAGfish) (pack spec)
  - [noesisnoema-pipeline](https://github.com/raskolnikoff/noesisnoema-pipeline) (pack generator)

### Known Issues
- Performance on iOS simulators is limited (CPU fallback).
- Large RAGpacks may increase memory footprint.
- Some advanced llama.cpp features not yet surfaced in Swift.

---

## [Unreleased]
### Added
- Experimental support for GPT‑OSS‑20B (`gpt-oss-20b-Q4_K_S`, released 2025‑08‑08). Place the model at `Resources/Models/gpt-oss-20b-Q4_K_S.gguf` and select it in the LLM picker (macOS/iOS).
- LLM Presets (Pocket, Balanced, Pro Max) with device‑tuned defaults (threads, GPU layers, batch size, context length, decoding params).
- Liquid Glass design across macOS and iOS with accessibility‑aware fallbacks (respects Reduce Transparency; solid fallback).

### Notes
- Generation quality may vary or truncate under heavy device load/thermal throttling. The global generation lock prevents duplicate sends, and the streaming filter + final normalizer remove `<think>` and control tokens. Adjust `n_threads` first, then `n_gpu_layers` if throttling occurs.

### Planned
- iPad-optimized layouts and sharing/export on iOS
- Enhanced right pane with chunk/source previews
- Device-optimal presets (threads, Metal layers)
- Peer-to-peer sync without cloud
- Plugin/API extensibility
- CI setup for app targets
