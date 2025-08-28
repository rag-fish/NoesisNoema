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
### Planned
- iPad-optimized layouts and sharing/export on iOS
- Enhanced right pane with chunk/source previews
- Device-optimal presets (threads, Metal layers)
- Peer-to-peer sync without cloud
- Plugin/API extensibility
- CI setup for app targets
