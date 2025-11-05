Title: Default LLM selection, sandbox-safe RAGPack access, and double-submit guard for Ask button (macOS & iOS)

Context & Constraints
- App: Noesis Noema (Swift-only). LLM runs fully local via llama.cpp xcframeworks built outside Xcode (CLion script).
- Keep architecture: no CoreML/MLPackage, no tokenizer, Swift native, offline-first.
- RAGPack is user-chosen (local or Google Drive import), then indexed; no auto-scan of user folders at launch.
- Current issues (see errors.txt):
- Picker: the selection "Jan-V1-4B" is invalid and does not have an associated tag → Picker selection/tag mismatch.
- Sandbox error when scanning ~/Downloads → NSCocoaErrorDomain Code=257.
- App can get stuck (“Message from debugger: killed”) after small query post-RAGPack.
- Ask button can be tapped twice (Xcode26 migration lost the lock).

Goals
	1.	Default LLM selection
- After ModelRegistry finishes discovery/registration, automatically set a valid default LLM (first available or user’s last choice if present).
- Fix SwiftUI Picker to use a strongly-typed ModelID with .tag(ModelID) and @State/@Published selection: ModelID? that is guaranteed non-nil post-registry.
- If the previously selected model disappears, gracefully fallback to a valid one.
	2.	Sandbox-safe RAGPack access & no auto-scan
- Remove any automatic scanning of ~/Downloads or other non-container paths at app launch.
- Only scan:
- App bundle Resources/ (read-only models shipped)
- App container paths (Application Support/NoesisNoema, Documents/…)
- User-selected files/folders via NS/Open panel or previously stored security-scoped bookmarks (start/stop accessing properly).
- When user picks a RAGPack file/folder, create & persist a security-scoped bookmark; re-validate on next launch. If invalid, prompt the user to re-grant.
- All file IO that may touch outside the container must be wrapped with startAccessingSecurityScopedResource() + defer stop….
	3.	Ask button double-submit guard & UI state
- Introduce @Published var isGenerating = false in ChatViewModel.
- Ask flow: guard !isGenerating → set isGenerating = true → run async generation → ensure isGenerating = false in defer.
- In SwiftUI, .disabled(isGenerating) on Ask button; show a small ProgressView and prevent multiple presses.
- Debounce user keystrokes / Enter-to-send or use a short throttle (e.g., 300–500ms) if needed.
	4.	Stability after RAGPack import
- Ensure model & vector store readiness checks before allowing Ask:
- guard selectedModel != nil && VectorStore.shared.indexIsReady
- If not ready, show inline warning and disable Ask.
- All registry or index callbacks must hop to MainActor before mutating SwiftUI state.

Files to Modify (typical locations)
- NoesisNoema/Shared/ModelRegistry.swift
- Add completion publisher/async method onRegistryReady → set default model.
- Expose [ModelInfo] → convert to [ModelID: ModelInfo].
- NoesisNoema/Shared/ViewModels/ChatViewModel.swift
- Add @Published var isGenerating = false, @Published var selectedModel: ModelID?.
- In ask() guard against isGenerating, guard against nil model & unready index.
- Ensure every async path resets isGenerating = false in defer.
- NoesisNoema/Shared/Views/ModelPickerView.swift (or wherever the Picker lives)
- Define enum ModelID: String, CaseIterable, Identifiable { … } (id = rawValue).
- For each row: .tag(model.id); Picker selection is Binding<ModelID>.
- Provide a non-nil default from registry when view appears.
- NoesisNoema/Shared/DocumentManager.swift (and any RAG import pipeline)
- Remove auto-scan of ~/Downloads.
- Add helpers:
```swift
func withSecurityScopedURL<T>(_ url: URL, _ work: () throws -> T) rethrows -> T
func persistBookmark(for url: URL) throws
func resolveBookmark(data: Data) -> URL?
```

- Use these in import & open flows; scan only within app container + user-granted URLs.

- NoesisNoema/Shared/Views/ChatView.swift (or ContentView.swift)
- Bind .disabled(viewModel.isGenerating) to Ask button; show ProgressView when true.
- Guard against empty prompt or not-ready states.

Key Code Changes (high-level, let Copilot fill in)
- Strongly typed ModelID and correct .tag() wiring.
- Default selection logic, e.g.:
```swift
registry.onReady { models in
    await MainActor.run {
        if let keep = UserDefaults.standard.lastModelID, models[keep] != nil {
            viewModel.selectedModel = keep
        } else {
            viewModel.selectedModel = models.keys.sorted().first
        }
    }
}
```

- Replace any eager FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Users/.../Downloads")…) with container-only scans.
- Wrap non-container URLs with security-scoped access before reading.

Acceptance Criteria
- App launches without sandbox errors (no NSCocoaErrorDomain 257).
- Model Picker shows tags correctly; a valid default model is already selected.
- After importing a RAGPack, UI refreshes and Ask becomes enabled only when index is ready.
- Pressing Ask twice rapidly never triggers concurrent requests; button disables & shows progress.
- No unexpected “killed” after a short query; if a failure occurs, user gets a readable inline error and the UI fully recovers (isGenerating resets).

Out of Scope / Do Not Change
- Do not rebuild xcframeworks inside Xcode. They are produced by CLion script and already copied under:
- NoesisNoema/NoesisNoema/Frameworks/xcframeworks/llama_macos.xcframework
- NoesisNoema/NoesisNoema/Frameworks/xcframeworks/llama_ios.xcframework
- Do not introduce CoreML/MLPackage/tokenizer. Keep Swift-only + llama.cpp.

After you finish
	1.	Build & run macOS target. Verify:
- Default LLM is selected on first launch.
- Import a RAGPack (user-selected path) → no permissions error; index ready.
- Ask once → button disables; after completion, re-enables.
	2.	Build & run iOS target. Verify same UX.
	3.	Commit with:

```bash
git checkout -b feature/llm-default-sandbox-ask-guard
git add .
git commit -m "fix: default LLM selection, sandbox-safe RAGPack access, double-submit guard"
```
