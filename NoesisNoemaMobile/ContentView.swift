//
//  ContentView.swift
//  NoesisNoemaMobile
//
//  Created by Раскольников on 2025/08/15.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {

    @StateObject private var documentManager = DocumentManager()

    @State private var question: String = ""
    @State private var isLoading: Bool = false
    @State private var selectedEmbeddingModel: String = "default-embedding"
    @State private var selectedLLMModel: String = "Jan-V1-4B"
    // 新規: LLMプリセット選択（iOS）
    @State private var selectedLLMPreset: String = ModelManager.shared.currentLLMPreset

    // 新規: オートチューン状態（iOS）
    @State private var isAutotuningModel: Bool = false
    @State private var recommendedReady: Bool = false
    @State private var autotuneWarning: String? = nil

    // ランタイムモード（推奨/上書き）
    @State private var runtimeMode: RuntimeMode = ModelManager.shared.getRuntimeMode()

    @State private var showImporter = false
    @State private var showSplash = true
    @FocusState private var questionFocused: Bool

    var availableEmbeddingModels: [String] { ModelManager.shared.availableEmbeddingModels }
    var availableLLMModels: [String] { ModelManager.shared.availableLLMModels }
    // 新規: プリセット候補（iOS）
    var availableLLMPresets: [String] { ModelManager.shared.availableLLMPresets }

    var body: some View {
        NavigationView {
            mainContent
        }
    }

    // MARK: - Main Content
    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 12) {
            topSettingsSection
            Divider()
            historySection
        }
        .frame(maxHeight: .infinity)
        .disabled(isLoading)
        .navigationTitle("Noesis Noema")
        .toolbarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .overlay(overlayContent)
    }

    // MARK: - Top Settings Section
    @ViewBuilder
    private var topSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            modelPickersRow
            runtimeModeRow
            presetPicker
            autotuneWarningView
            questionInputSection
            actionButtonsRow
        }
        .padding(.horizontal)
        .onAppear { runtimeMode = ModelManager.shared.getRuntimeMode() }
        .contentShape(Rectangle())
        .onTapGesture { questionFocused = false }
    }

    // MARK: - Model Pickers Row
    @ViewBuilder
    private var modelPickersRow: some View {
        HStack {
            Picker("Embedding", selection: $selectedEmbeddingModel) {
                ForEach(availableEmbeddingModels, id: \.self) { Text($0) }
            }
            .pickerStyle(MenuPickerStyle())
            .onChange(of: selectedEmbeddingModel) { oldValue, newValue in
                ModelManager.shared.switchEmbeddingModel(name: newValue)
            }

            Spacer(minLength: 16)

            llmPickerSection
        }
    }

    // MARK: - LLM Picker Section
    @ViewBuilder
    private var llmPickerSection: some View {
        HStack(spacing: 8) {
            Picker("LLM", selection: $selectedLLMModel) {
                ForEach(availableLLMModels, id: \.self) { Text($0) }
            }
            .pickerStyle(MenuPickerStyle())
            .onChange(of: selectedLLMModel) { oldValue, newValue in
                handleLLMModelChange(newValue)
            }

            llmStatusBadge
        }
    }

    // MARK: - LLM Status Badge
    @ViewBuilder
    private var llmStatusBadge: some View {
        if isAutotuningModel {
            ProgressView().scaleEffect(0.8)
        } else {
            if runtimeMode == .override {
                Text("Custom")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12), in: Capsule())
            } else if recommendedReady {
                Text("Recommended")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.12), in: Capsule())
            }
        }
    }

    // MARK: - Runtime Mode Row
    @ViewBuilder
    private var runtimeModeRow: some View {
        HStack(spacing: 12) {
            Picker("Runtime Params", selection: $runtimeMode) {
                Text("Use recommended").tag(RuntimeMode.recommended)
                Text("Override").tag(RuntimeMode.override)
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: runtimeMode) { oldValue, newValue in
                ModelManager.shared.setRuntimeMode(newValue)
                if newValue == .recommended { recommendedReady = true }
            }
            .accessibilityLabel(Text("Runtime parameters mode"))

            Button("Reset") {
                ModelManager.shared.resetToRecommended()
                runtimeMode = .recommended
                recommendedReady = true
            }
            .disabled(runtimeMode != .override)
            .accessibilityLabel(Text("Reset to recommended parameters"))
        }
    }

    // MARK: - Preset Picker
    @ViewBuilder
    private var presetPicker: some View {
        Picker("LLM Preset", selection: $selectedLLMPreset) {
            ForEach(availableLLMPresets, id: \.self) { p in
                Text(p)
            }
        }
        .pickerStyle(MenuPickerStyle())
        .onChange(of: selectedLLMPreset) { oldValue, newValue in
            ModelManager.shared.setLLMPreset(name: newValue)
        }
        .disabled(isLoading)
    }

    // MARK: - Autotune Warning
    @ViewBuilder
    private var autotuneWarningView: some View {
        if let warn = autotuneWarning {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(warn)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Question Input
    @ViewBuilder
    private var questionInputSection: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $question)
                .frame(height: 100)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.15))
                )
                .disabled(isLoading)
                .focused($questionFocused)
            if question.isEmpty {
                Text("Enter your question")
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            }
        }
    }

    // MARK: - Action Buttons
    @ViewBuilder
    private var actionButtonsRow: some View {
        HStack(spacing: 12) {
            Button(action: { startAsk() }) {
                Text(isLoading ? "Asking..." : "Ask")
                    .frame(maxWidth: .infinity)
            }
            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(minHeight: 52)

            Button {
                showImporter = true
            } label: {
                Text("Choose RAGpack")
                    .frame(maxWidth: .infinity)
            }
            .disabled(isLoading)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(minHeight: 52)
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType.zip]) { result in
                if case let .success(url) = result {
                    documentManager.importDocument(file: url)
                }
            }
        }
    }

    // MARK: - History Section
    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History").font(.headline)

            ZStack(alignment: .bottom) {
                historyList
                qaDetailOverlay
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal)
        .frame(maxHeight: .infinity)
    }

    // MARK: - History List
    @ViewBuilder
    private var historyList: some View {
        List {
            ForEach(documentManager.qaHistory) { qa in
                VStack(alignment: .leading) {
                    Text(qa.question).font(.subheadline).bold()
                    Text(qa.answer).font(.caption).lineLimit(3).foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isLoading {
                        questionFocused = false
                        documentManager.selectedQAPair = qa
                    }
                }
            }
            .onDelete { offsets in
                if !isLoading { documentManager.deleteQAPair(at: offsets) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(.clear)
        .scrollDismissesKeyboard(.immediately)
        .disabled(documentManager.selectedQAPair != nil || isLoading)
    }

    // MARK: - QA Detail Overlay
    @ViewBuilder
    private var qaDetailOverlay: some View {
        if let selected = documentManager.selectedQAPair {
            QADetailView(qapair: selected, onClose: { if !isLoading { documentManager.selectedQAPair = nil } })
                .padding(.horizontal)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
        }
    }

    // MARK: - Overlay Content
    @ViewBuilder
    private var overlayContent: some View {
        Group {
            loadingOverlay
            splashScreen
        }
    }

    // MARK: - Loading Overlay
    @ViewBuilder
    private var loadingOverlay: some View {
        if isLoading {
            ZStack {
                Color.black.opacity(0.05).ignoresSafeArea()
                VStack(spacing: 8) {
                    ProgressView().scaleEffect(1.2)
                    Text("Generating...")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .allowsHitTesting(true)
            .zIndex(2)
        }
    }

    // MARK: - Splash Screen
    @ViewBuilder
    private var splashScreen: some View {
        if showSplash {
            ZStack {
                Color.clear.ignoresSafeArea()
                Text("Noesis Noema")
                    .font(.largeTitle.bold())
                    .foregroundColor(.primary)
                    .padding(.bottom, 24)
            }
            .transition(.opacity)
            .zIndex(3)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeOut(duration: 0.3)) { showSplash = false }
                }
            }
            .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showSplash = false } }
        }
    }

    // MARK: - Helper Methods
    private func handleLLMModelChange(_ newValue: String) {
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
            if !warningMessage.isEmpty { autotuneWarning = warningMessage }
        }
    }

    @MainActor
    private func askRAG() async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isLoading else { return }
        // 入力確定とキーボード閉じ
        question = trimmed
        questionFocused = false
        isLoading = true
        let result = await ModelManager.shared.generateAsyncAnswer(question: question)
        documentManager.addQAPair(question: question, answer: result)
        question = ""
        isLoading = false
    }

    private func startAsk() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isLoading else { return }
        // ここで同期的にロックし、二重タップのレースを遮断
        question = trimmed
        questionFocused = false
        isLoading = true
        Task { @MainActor in
            let result = await ModelManager.shared.generateAsyncAnswer(question: question)
            let newPair = documentManager.addQAPair(question: question, answer: result)
            // Cache: 保存（ソースは ModelManager.shared.lastRetrievedChunks）
            let sources = ModelManager.shared.lastRetrievedChunks
            QAContextStore.shared.put(qaId: newPair.id, question: newPair.question, answer: newPair.answer, sources: sources, embedder: ModelManager.shared.currentEmbeddingModel)
            question = ""
            isLoading = false
        }
    }
}

#Preview {
    ContentView()
}
