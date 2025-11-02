//
//  MobileHomeView.swift
//  NoesisNoemaMobile
//
//  Full-screen iOS redesign for Noesis Noema
//  iOS 18+ optimized layout with proper safe area handling
//

import SwiftUI
import UniformTypeIdentifiers

struct MobileHomeView: View {
    @StateObject private var documentManager = DocumentManager()

    @State private var question: String = ""
    @State private var isLoading: Bool = false
    @State private var selectedLLMModel: String = "Jan-V1-4B"
    @State private var selectedLLMPreset: String = ModelManager.shared.currentLLMPreset

    @State private var isAutotuningModel: Bool = false
    @State private var recommendedReady: Bool = false
    @State private var autotuneWarning: String? = nil

    @State private var runtimeMode: RuntimeMode = ModelManager.shared.getRuntimeMode()
    @State private var showImporter = false
    @State private var showSplash = true

    @FocusState private var questionFocused: Bool
    
    private let splashScreenDuration: TimeInterval = 1.2

    var availableEmbeddingModels: [String] { ModelManager.shared.availableEmbeddingModels }
    var availableLLMModels: [String] { ModelManager.shared.availableLLMModels }
    var availableLLMPresets: [String] { ModelManager.shared.availableLLMPresets }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Mode Picker Section
                    modePickerSection

                    // Model Selector Section
                    modelSelectorSection

                    // Prompt Input Section
                    promptInputSection

                    // Action Buttons
                    actionButtonsSection

                    // History Section
                    historySection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .navigationTitle("Noesis Noema")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
        }
        .overlay(overlayContent)
        .onAppear {
            runtimeMode = ModelManager.shared.getRuntimeMode()
        }
    }

    // MARK: - Mode Picker Section

    @ViewBuilder
    private var modePickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Runtime Parameters")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Picker("", selection: $runtimeMode) {
                    Text("Use recommended").tag(RuntimeMode.recommended)
                    Text("Override").tag(RuntimeMode.override)
                }
                .pickerStyle(.segmented)
                .onChange(of: runtimeMode) { oldValue, newValue in
                    ModelManager.shared.setRuntimeMode(newValue)
                    if newValue == .recommended {
                        recommendedReady = true
                    }
                }
                .accessibilityLabel("Runtime parameters mode")

                Button("Reset") {
                    resetAll()
                }
                .buttonStyle(.bordered)
                .disabled(runtimeMode != .override)
                .accessibilityLabel("Reset to recommended parameters")
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Model Selector Section

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
                .onChange(of: selectedLLMPreset) { oldValue, newValue in
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

    // MARK: - Prompt Input Section

    @ViewBuilder
    private var promptInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Question")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $question)
                    .frame(minHeight: 120, maxHeight: 220)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(questionFocused ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: questionFocused ? 2 : 1)
                    )
                    .focused($questionFocused)
                    .disabled(isLoading)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                questionFocused = false
                            }
                        }
                    }

                if question.isEmpty {
                    Text("Enter your question")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Spacer()
                Text("\(question.count) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Action Buttons Section

    @ViewBuilder
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Button(action: { startAsk() }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    Text(isLoading ? "Asking..." : "Ask")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            .accessibilityLabel("Submit question")

            Button(action: { showImporter = true }) {
                Label("Choose RAG Document", systemImage: "doc.zipper")
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.bordered)
            .disabled(isLoading)
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType.zip]
            ) { result in
                if case let .success(url) = result {
                    documentManager.importDocument(file: url)
                }
            }
            .accessibilityLabel("Import RAG document")
        }
    }

    // MARK: - History Section

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.top, 8)

            if documentManager.qaHistory.isEmpty {
                emptyHistoryView
            } else {
                historyList
            }
        }
    }

    @ViewBuilder
    private var emptyHistoryView: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No questions yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Ask a question to get started")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private var historyList: some View {
        LazyVStack(spacing: 12) {
            ForEach(documentManager.qaHistory) { qa in
                HistoryCard(qa: qa, isLoading: isLoading) {
                    if !isLoading {
                        questionFocused = false
                        documentManager.selectedQAPair = qa
                    }
                }
            }
        }
    }

    // MARK: - Overlay Content

    @ViewBuilder
    private var overlayContent: some View {
        Group {
            qaDetailOverlay
            splashScreen
        }
    }

    @ViewBuilder
    private var qaDetailOverlay: some View {
        if let selected = documentManager.selectedQAPair {
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if !isLoading {
                            documentManager.selectedQAPair = nil
                        }
                    }

                VStack {
                    QADetailView(qapair: selected, onClose: {
                        if !isLoading {
                            documentManager.selectedQAPair = nil
                        }
                    })
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding()
                }
            }
            .transition(.opacity)
            .zIndex(1)
        }
    }

    @ViewBuilder
    private var splashScreen: some View {
        if showSplash {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 72))
                        .foregroundStyle(.tint)

                    Text("Noesis Noema")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
            }
            .transition(.opacity)
            .zIndex(2)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + splashScreenDuration) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showSplash = false
                    }
                }
            }
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.2)) {
                    showSplash = false
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func resetAll() {
        ModelManager.shared.resetToRecommended()
        runtimeMode = .recommended
        recommendedReady = true
        question = ""
    }

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
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isLoading else { return }

        question = trimmed
        questionFocused = false
        isLoading = true

        Task { @MainActor in
            let result = await ModelManager.shared.generateAsyncAnswer(question: question)
            let newPair = documentManager.addQAPair(question: question, answer: result)

            let sources = ModelManager.shared.lastRetrievedChunks
            QAContextStore.shared.put(
                qaId: newPair.id,
                question: newPair.question,
                answer: newPair.answer,
                sources: sources,
                embedder: ModelManager.shared.currentEmbeddingModel
            )

            question = ""
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

struct HistoryCard: View {
    let qa: QAPair
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.tint)

                    Text(qa.question)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(.secondary)

                    Text(qa.answer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

#Preview {
    MobileHomeView()
}
