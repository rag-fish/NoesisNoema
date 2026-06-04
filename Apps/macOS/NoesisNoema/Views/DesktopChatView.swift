//
//  DesktopChatView.swift
//  NoesisNoema (macOS)
//
//  ADR-0010 Chat section. A model/preset header, an inline conversation
//  transcript, and a bottom-pinned question input. The transcript renders the
//  shared `DocumentManager.qaHistory` as a conversation so an answer appears
//  HERE immediately after asking; the browsable archive lives in the History
//  section.
//
//  Inference is routed through `executionCoordinator.execute(request:)`
//  (ADR-0010 §3 / ADR-0008 R2) — NOT `ModelManager.generateAsync*`. Session
//  memory is wired identically to iOS (PR #87 / ADR-0009): the UI pre-applies
//  the 3-turn AND 45-minute caps via `SessionMemory.history(from:)` and carries
//  exactly that in the request. Citations propagate on the response
//  (`NoemaResponse.sources`) and are stashed in `QAContextStore` for History.
//
//  Mirrors `MobileHomeView` for STRUCTURE only; written fresh for macOS
//  (semantic NSColor backgrounds, `SafeTextInput` for IME-safe entry).
//

#if os(macOS)
import SwiftUI

struct DesktopChatView: View {
    /// Shared QA/document store, injected by `DesktopRootView` so Chat, History,
    /// and Settings all observe the same instance.
    @ObservedObject var documentManager: DocumentManager

    @State private var question: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    @State private var selectedLLMPreset: String = ModelManager.shared.currentLLMPreset
    @State private var selectedLLMModel: String = ModelManager.shared.currentLLMModel.name

    @State private var isAutotuningModel: Bool = false
    @State private var recommendedReady: Bool = false
    @State private var autotuneWarning: String? = nil

    /// Hybrid runtime entry point. In the app this is the single coordinator
    /// threaded from `@main`; the default exists only for `#Preview`/tests.
    private let executionCoordinator: ExecutionCoordinating

    /// Auto-scroll anchor for the in-flight "Generating…" indicator.
    private static let loadingIndicatorID = "transcript.loading.indicator"

    init(
        documentManager: DocumentManager,
        executionCoordinator: ExecutionCoordinating = HybridExecutionCoordinator()
    ) {
        self.documentManager = documentManager
        self.executionCoordinator = executionCoordinator
    }

    private var availableLLMModels: [String] { ModelManager.shared.availableLLMModels }
    private var availableLLMPresets: [String] { ModelManager.shared.availableLLMPresets }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            transcript

            Divider()

            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("Chat")
        .alert(
            "Couldn’t generate an answer",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { presented in if !presented { errorMessage = nil } }
            ),
            presenting: errorMessage
        ) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Header (model / preset)

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Model")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(selectedLLMModel)
                        .font(.headline)
                    if isAutotuningModel {
                        ProgressView().scaleEffect(0.7)
                    } else if recommendedReady {
                        DesktopBadge(text: "Recommended", color: .green)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Text("Preset")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Preset", selection: $selectedLLMPreset) {
                    ForEach(availableLLMPresets, id: \.self) { preset in
                        Text(preset).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 140)
                .onChange(of: selectedLLMPreset) { _, newValue in
                    ModelManager.shared.setLLMPreset(name: newValue)
                }
                .disabled(isLoading)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let warning = autotuneWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .offset(y: 22)
            }
        }
        .onAppear {
            selectedLLMModel = ModelManager.shared.currentLLMModel.name
            selectedLLMPreset = ModelManager.shared.currentLLMPreset
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if documentManager.qaHistory.isEmpty && !isLoading {
                    emptyState
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(documentManager.qaHistory) { qa in
                            DesktopChatTurn(qa: qa)
                                .id(qa.id)
                        }
                        if isLoading {
                            generatingIndicator
                                .id(Self.loadingIndicatorID)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: documentManager.qaHistory.count) { _, _ in
                scrollToLatest(proxy)
            }
            .onChange(of: isLoading) { _, _ in
                scrollToLatest(proxy)
            }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if isLoading {
                proxy.scrollTo(Self.loadingIndicatorID, anchor: .bottom)
            } else if let last = documentManager.qaHistory.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Ask me anything.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var generatingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7)
            Text("Generating…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            SafeTextInput(
                text: $question,
                placeholder: "Type your question…",
                onSubmit: startAsk,
                isEnabled: !isLoading
            )
            .frame(minHeight: 38, maxHeight: 96)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )

            Button(action: startAsk) {
                if isLoading {
                    ProgressView().scaleEffect(0.7).frame(width: 22, height: 22)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(isLoading || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Submit question")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Ask

    private func startAsk() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isLoading else { return }

        question = trimmed
        isLoading = true

        // ADR-0009 / ADR-0010 §3: session memory is the visible transcript only.
        // The UI is the source of truth, so it pre-applies BOTH caps (3 turns AND
        // the 45-minute window) via the shared helper before building the
        // request — the executor sees exactly what the user sees.
        let history = SessionMemory.history(from: documentManager.qaHistory)

        Task { @MainActor in
            do {
                // ADR-0010 §3 / ADR-0008 R2: route through the coordinator; the
                // heavy RAG + llama work runs off-main inside the executor.
                let response = try await executionCoordinator.execute(
                    request: NoemaRequest(query: trimmed, history: history)
                )

                let newPair = documentManager.addQAPair(
                    question: trimmed,
                    answer: response.text
                )

                // Citations arrive on the response (ExecutionResult.sources →
                // NoemaResponse.sources). Stash per-QA context so the History
                // section can render citations and feedback can cache.
                QAContextStore.shared.put(
                    qaId: newPair.id,
                    question: newPair.question,
                    answer: newPair.answer,
                    sources: response.sources,
                    embedder: ModelManager.shared.currentEmbeddingModel
                )
                question = ""
            } catch {
                // ADR-0000: no silent fallback. Surface the failure; do NOT fall
                // back to a stub or to ModelManager as a backup.
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Supporting views

/// One conversation turn — question as a trailing bubble, answer below it.
/// macOS semantic colours so it adapts to light/dark appearance.
private struct DesktopChatTurn: View {
    let qa: QAPair

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer(minLength: 60)
                Text(qa.question)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack {
                Text(qa.answer)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Spacer(minLength: 60)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small pill badge (Recommended / Custom). macOS-local to avoid colliding with
/// the iOS `Badge` (which lives in the iOS-only view layer).
struct DesktopBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

#Preview {
    DesktopChatView(documentManager: DocumentManager())
        .environmentObject(AppSettings.shared)
        .frame(width: 600, height: 500)
}
#endif
