//
//  MobileHomeView.swift
//  NoesisNoemaMobile
//
//  Chat screen: a model/preset header, an inline conversation transcript, and
//  a bottom-pinned question input. The transcript renders documentManager's
//  Q&A pairs as a conversation so an answer appears HERE immediately after
//  asking — no History-tab round-trip (UAT #3). The browsable archive lives in
//  the History tab; the Chat tab no longer embeds a history list (UAT #4).
//

import SwiftUI

struct MobileHomeView: View {
    /// Shared QA/document store, injected by `TabRootView` so the Chat tab,
    /// History tab, and Settings tab all observe the same instance.
    @ObservedObject var documentManager: DocumentManager

    @State private var question: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var selectedLLMModel: String = "Llama 3.2 3B"
    @State private var selectedLLMPreset: String = ModelManager.shared.currentLLMPreset

    @State private var isAutotuningModel: Bool = false
    @State private var recommendedReady: Bool = false
    @State private var autotuneWarning: String? = nil

    @State private var runtimeMode: RuntimeMode = ModelManager.shared.getRuntimeMode()

    @FocusState private var questionFocused: Bool

    /// Hybrid runtime entry point. R2 (ADR-0008 Decision 1) routes
    /// MobileHomeView inference through this coordinator instead of calling the
    /// ModelManager monolith directly.
    private let executionCoordinator: ExecutionCoordinating

    /// Anchor id for the in-flight "Generating…" indicator (auto-scroll target).
    private static let loadingIndicatorID = "transcript.loading.indicator"

    /// - Parameters:
    ///   - documentManager: Shared QA/document store (injected by `TabRootView`).
    ///   - executionCoordinator: Hybrid runtime entry point. In the app this is
    ///     the single coordinator threaded from `@main`; the default
    ///     (`HybridExecutionCoordinator()`) exists only for `#Preview`/tests.
    init(
        documentManager: DocumentManager,
        executionCoordinator: ExecutionCoordinating = HybridExecutionCoordinator()
    ) {
        self.documentManager = documentManager
        self.executionCoordinator = executionCoordinator
    }

    var availableLLMModels: [String] { ModelManager.shared.availableLLMModels }
    var availableLLMPresets: [String] { ModelManager.shared.availableLLMPresets }

    var body: some View {
        VStack(spacing: 0) {
            modelSelectorSection
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            transcriptSection

            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear {
            runtimeMode = ModelManager.shared.getRuntimeMode()
        }
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

    // MARK: - Model Selector Section (acts as the chat header)

    @ViewBuilder
    private var modelSelectorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Current Model Display
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Model")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(selectedLLMModel)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if isAutotuningModel {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if runtimeMode == .override {
                            Badge(text: "Custom", color: .orange)
                        } else if recommendedReady {
                            Badge(text: "Recommended", color: .green)
                        }
                    }
                }

                Spacer()

                Menu {
                    ForEach(availableLLMModels, id: \.self) { model in
                        Button(model) {
                            handleLLMModelChange(model)
                        }
                    }
                } label: {
                    Label("Change", systemImage: "chevron.down.circle")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }

            // Preset Picker
            HStack {
                Text("Preset")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Preset", selection: $selectedLLMPreset) {
                    ForEach(availableLLMPresets, id: \.self) { preset in
                        Text(preset).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedLLMPreset) { newValue in
                    ModelManager.shared.setLLMPreset(name: newValue)
                }
                .disabled(isLoading)
            }

            // Autotune Warning
            if let warning = autotuneWarning {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Conversation Transcript

    /// The live conversation. Renders `documentManager.qaHistory` as chat turns
    /// (question bubble + answer) so the answer is visible on the Chat tab the
    /// moment `startAsk()` completes. Auto-scrolls to the newest turn.
    private var transcriptSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if documentManager.qaHistory.isEmpty && !isLoading {
                    emptyTranscript
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(documentManager.qaHistory) { qa in
                            QATurnView(qa: qa)
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
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: documentManager.qaHistory.count) { _ in
                scrollToLatest(proxy)
            }
            .onChange(of: isLoading) { _ in
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

    private var emptyTranscript: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Ask me anything.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
    }

    private var generatingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Generating…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Input Bar (pinned to the bottom)

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Type your question…", text: $question)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .focused($questionFocused)
                .disabled(isLoading)
                .onSubmit(startAsk)

            Button(action: startAsk) {
                ZStack {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                    }
                }
                .frame(width: 32, height: 32)
            }
            .disabled(isLoading || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Submit question")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Helper Methods

    private func handleLLMModelChange(_ newValue: String) {
        selectedLLMModel = newValue
        recommendedReady = false
        autotuneWarning = nil
        isAutotuningModel = true

        ModelManager.shared.switchLLMModel(name: newValue)
        runtimeMode = ModelManager.shared.getRuntimeMode()
        selectedLLMPreset = "auto"
        ModelManager.shared.setLLMPreset(name: "auto")

        ModelManager.shared.autotuneCurrentModelAsync(trace: false, timeoutSeconds: 3.0) { warningMessage in
            isAutotuningModel = false
            recommendedReady = true
            if !warningMessage.isEmpty {
                autotuneWarning = warningMessage
            }
        }
    }

    private func startAsk() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🎬 [iOS/MobileHomeView] startAsk CALLED")
        print("   Question: \(question.prefix(50))...")

        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isLoading else { return }

        question = trimmed
        questionFocused = false
        isLoading = true

        // R2 (ADR-0008 Decision 1): route inference through the execution
        // coordinator instead of calling the ModelManager monolith directly.
        // The heavy RAG + llama work runs off the main thread inside the
        // executor (LocalExecutor hops off-main for retrieval and inference);
        // this @MainActor Task only marshals UI state and the QA store.
        Task { @MainActor in
            do {
                let response = try await executionCoordinator.execute(
                    request: NoemaRequest(query: trimmed)
                )

                let newPair = documentManager.addQAPair(
                    question: trimmed,
                    answer: response.text
                )

                // Citations now arrive on the response (ExecutionResult.sources
                // → NoemaResponse.sources) instead of via ModelManager's mutable
                // `lastRetrievedChunks` side effect. `embedder` is model/config,
                // not inference — reading it from ModelManager stays (ADR-0008).
                QAContextStore.shared.put(
                    qaId: newPair.id,
                    question: newPair.question,
                    answer: newPair.answer,
                    sources: response.sources,
                    embedder: ModelManager.shared.currentEmbeddingModel
                )
                question = ""
            } catch {
                // ADR-0000: no silent fallback. Surface the failure to the user;
                // do NOT fall back to a stub or to ModelManager as a backup.
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Supporting Views

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

/// One conversation turn — the question as a trailing bubble, the answer below
/// it. Uses semantic colors so it adapts to light/dark mode.
private struct QATurnView: View {
    let qa: QAPair

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer(minLength: 48)
                Text(qa.question)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            HStack {
                Text(qa.answer)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Spacer(minLength: 48)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    MobileHomeView(documentManager: DocumentManager())
}
