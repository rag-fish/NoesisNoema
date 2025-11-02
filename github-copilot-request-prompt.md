Title: iOS UI full-screen redesign for NoesisNoemaMobile (SwiftUI)



Context:
	•	Project: NoesisNoema.xcodeproj
	•	Target: NoesisNoemaMobile (iOS only)
	•	Platform: Xcode 26 / iOS 18 SDK
	•	Shared logic (Shared/, RAG/, etc.) must remain unchanged.
	•	xcframeworks (llama_ios.xcframework, etc.) must not be modified.
	•	macOS target (NoesisNoema) and CLI target (LlamaBridgeTest) are out of scope.
	•	The current iOS UI works but is poorly scaled under iOS 18 — elements overlap and waste screen space.



🎯 Goal

Redesign the iOS UI layout in SwiftUI so it:
	•	Uses the full screen area gracefully (safe areas respected).
	•	Feels touch-friendly, readable, and consistent with iOS 18’s new design system.
	•	Keeps all functional bindings intact (prompt input, mode switch, history).
	•	Avoids breaking build for macOS or CLI.



✅ Requirements
	1.	Navigation
	•	Use NavigationStack with .navigationBarTitleDisplayMode(.inline).
	•	Title: “Noesis Noema” (centered, compact header).
	•	Remove unnecessary top padding or spacers.
	2.	Layout hierarchy (vertical scrollable stack)
	•	Mode switch (segmented control): “Use recommended” / “Override” + right-side “Reset” button.
	•	Model selector row: shows current model (e.g. "auto") and a “Change model” button.
	•	Multiline prompt editor with placeholder "Enter your question" and character counter.
	•	Two primary buttons stacked:
	•	Ask (primary, full width, height ≥ 48pt)
	•	Choose RAG… (secondary)
	•	“History” heading followed by the scrollable history list.
	3.	Layout and spacing
	•	Horizontal padding: 16–20pt
	•	Vertical spacing between sections: 12–16pt
	•	Dynamic type ready (.minimumScaleFactor(0.9))
	•	Works correctly on iPhone SE (3rd gen) and iPhone 16 Pro Max.
	•	Input field and buttons remain visible when keyboard is open
(.ignoresSafeArea(.keyboard) and ScrollView adjustments).
	4.	Accessibility
	•	Buttons and toggles include accessibilityLabels.
	•	Support both dark and light mode with readable contrast.
	5.	Code constraints
	•	Create new iOS-specific view under:
NoesisNoemaMobile/Views/MobileHomeView.swift
	•	Modify NoesisNoemaMobileApp.swift so the app loads this new view.
	•	Keep Shared/ContentView.swift intact (macOS version still uses it).
	•	Optionally use #if os(iOS) guards if shared files must import the new layout.
	•	Do not modify or rename existing business logic or models.



🧩 Suggested structure

```swift
// NoesisNoemaMobile/Views/MobileHomeView.swift
import SwiftUI

struct MobileHomeView: View {
    @State private var mode: Mode = .recommended
    @State private var modelName = "auto"
    @State private var prompt = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // Mode Picker
                    HStack(spacing: 12) {
                        Picker("", selection: $mode) {
                            Text("Use recommended").tag(Mode.recommended)
                            Text("Override").tag(Mode.override)
                        }
                        .pickerStyle(.segmented)
                        Button("Reset") { resetAll() }
                            .buttonStyle(.bordered)
                    }

                    // Model selector
                    HStack {
                        Text(modelName).font(.headline).foregroundStyle(.tint)
                        Spacer()
                        Button("Change model") { presentModelPicker() }
                    }

                    // Prompt input
                    VStack(alignment: .leading, spacing: 8) {
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $prompt)
                                .frame(minHeight: 120, maxHeight: 220)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.25)))
                                .focused($focused)
                                .toolbar {
                                    ToolbarItemGroup(placement: .keyboard) {
                                        Spacer()
                                        Button("Done") { focused = false }
                                    }
                                }

                            if prompt.isEmpty {
                                Text("Enter your question")
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 16)
                            }
                        }

                        HStack {
                            Spacer()
                            Text("\(prompt.count) chars")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Buttons
                    VStack(spacing: 12) {
                        Button(action: ask) {
                            Text("Ask")
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button(action: chooseRAG) {
                            Text("Choose RAG…")
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.bordered)
                    }

                    // History section
                    Text("History")
                        .font(.title3.bold())
                        .padding(.top, 8)

                    HistoryListView()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .navigationTitle("Noesis Noema")
            .navigationBarTitleDisplayMode(.inline)
        }
        .ignoresSafeArea(.keyboard)
    }

    private func resetAll() { mode = .recommended; prompt = "" }
    private func presentModelPicker() { /* integrate existing picker */ }
    private func ask() { /* call existing ask logic */ }
    private func chooseRAG() { /* call existing RAG selection */ }

    enum Mode { case recommended, override }
}
```
---
```swift
// NoesisNoemaMobile/NoesisNoemaMobileApp.swift
import SwiftUI

@main
struct NoesisNoemaMobileApp: App {
    var body: some Scene {
        WindowGroup {
            MobileHomeView()
        }
    }
}
```



🧪 Validation checklist
	•	✅ Build succeeds for iOS target (NoesisNoemaMobile)
	•	✅ macOS & CLI targets unaffected
	•	✅ Layout renders properly on iPhone SE and iPhone 16 Pro Max
	•	✅ Buttons & inputs accessible under dark/light themes
	•	✅ Keyboard safe area behavior verified



Deliverables:
	•	New or updated SwiftUI files as described above
	•	Screenshots (Light/Dark, SE + 16 Pro Max)
	•	Short release note summarizing layout improvements
	•	Push all changes to feature/ui-layout-fix branch (draft PR acceptable)
