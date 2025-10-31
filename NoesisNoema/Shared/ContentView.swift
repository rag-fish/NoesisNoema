#if os(macOS)
//  ContentView.swift
//  NoesisNoema
//
//  Created by Раскольников on 2025/07/18.

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @EnvironmentObject var appSettings: AppSettings
    @State private var question: String = ""
    @State private var answer: String = ""
    @State private var isLoading: Bool = false
    @State private var selectedEmbeddingModel: String = ModelManager.shared.currentEmbeddingModel.name
    @State private var selectedLLMModel: String = ModelManager.shared.currentLLMModel.name
    // 新規: LLMプリセット選択
    @State private var selectedLLMPreset: String = ModelManager.shared.currentLLMPreset
    @State private var showRAGpackManager: Bool = false
    @StateObject private var documentManager = DocumentManager()

    @State private var qaHistory: [QAPair] = []
    @State private var selectedQAPair: QAPair? = nil

    // 新規: オートチューン状態
    @State private var isAutotuningModel: Bool = false
    @State private var recommendedReady: Bool = false
    @State private var autotuneWarning: String? = nil

    // ランタイムモード（推奨/上書き）
    @State private var runtimeMode: LLMRuntimeMode = .auto

    // これらは計算型プロパティにして初期化時の隔離制約を回避
    var availableEmbeddingModels: [String] { ModelManager.shared.availableEmbeddingModels }
    var availableLLMModels: [String] { ModelManager.shared.availableLLMModels }
    // 新規: プリセット候補
    var availableLLMPresets: [String] { ModelManager.shared.availableLLMPresets }

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .sheet(isPresented: $showRAGpackManager) {
            RAGpackManagerView(documentManager: documentManager)
        }
        .disabled(isLoading)
        .overlay(loadingOverlay)
    }

    // サイドバーコンテンツ
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button("New Question") {
                    selectedQAPair = nil
                    question = ""
                    answer = ""
                }
                .disabled(isLoading)
                Spacer()
                Button("Manage RAGpack") { showRAGpackManager.toggle() }
                    .disabled(isLoading)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.regularMaterial)

            List(selection: $selectedQAPair) {
                ForEach(qaHistory, id: \.id) { qa in
                    QAHistoryRow(qa: qa, isSelected: selectedQAPair?.id == qa.id)
                        .contentShape(Rectangle())
                        .onTapGesture { if !isLoading { selectedQAPair = qa } }
                }
                .onDelete { indexSet in
                    if !isLoading { qaHistory.remove(atOffsets: indexSet) }
                    if let selected = selectedQAPair, !qaHistory.contains(where: { $0.id == selected.id }) {
                        selectedQAPair = nil
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(.regularMaterial)
        .navigationTitle("Noesis Noema")
        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 360)
    }

    // 詳細コンテンツ
    private var detailContent: some View {
        Group {
            if let selected = selectedQAPair {
                QADetailView(qapair: selected, onClose: { if !isLoading { selectedQAPair = nil } })
                    .padding()
            } else {
                mainInputView
            }
        }
        .background(.ultraThinMaterial)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarBackground(.regularMaterial, for: .windowToolbar)
    }

    // メイン入力ビュー
    private var mainInputView: some View {
        ScrollView {
            VStack(spacing: 16) {
                offlineToggleRow
                embeddingModelPicker
                llmModelSection
                llmPresetPicker
                ragpackUploadSection
                questionInputSection
            }
            .padding(.vertical)
            .onAppear {
                runtimeMode = ModelManager.shared.getRuntimeMode()
            }
        }
        .background(.clear)
    }

    // オフライントグル行
    private var offlineToggleRow: some View {
        HStack(spacing: 12) {
            Toggle("Offline", isOn: $appSettings.offline)
                .toggleStyle(.switch)
                .help("When enabled, any remote calls are blocked.")
                .disabled(isLoading)
            if appSettings.offline && ModelManager.shared.isFullyLocal() {
                Text("Local Only")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12), in: Capsule())
                    .help("All components are local and remote calls are disabled.")
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    // 埋め込みモデルピッカー
    private var embeddingModelPicker: some View {
        Picker("Embedding Model", selection: $selectedEmbeddingModel) {
            ForEach(availableEmbeddingModels, id: \.self) { model in
                Text(model)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal)
        .onChange(of: selectedEmbeddingModel) { oldValue, newValue in
            ModelManager.shared.switchEmbeddingModel(name: newValue)
        }
        .disabled(isLoading)
    }

    // LLMモデルセクション
    private var llmModelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("LLM Model", selection: $selectedLLMModel) {
                    ForEach(availableLLMModels, id: \.self) { model in
                        Text(model)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedLLMModel) { oldValue, newValue in
                    recommendedReady = false
                    autotuneWarning = nil
                    isAutotuningModel = true
                    ModelManager.shared.switchLLMModel(name: newValue)
                    runtimeMode = ModelManager.shared.getRuntimeMode()
                    selectedLLMPreset = "auto"
                    ModelManager.shared.setLLMPreset(name: "auto")
                    ModelManager.shared.autotuneCurrentModelAsync(trace: false, timeoutSeconds: 3.0) { outcome in
                        isAutotuningModel = false
                        recommendedReady = true
                        // outcomeはString型なので直接表示
                        if !outcome.isEmpty {
                            autotuneWarning = outcome
                        }
                    }
                }

                if isAutotuningModel {
                    ProgressView().scaleEffect(0.7).padding(.leading, 8)
                } else {
                    if runtimeMode == .cpuOnly {
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

            runtimeParamsSection

            if let warn = autotuneWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(warn)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .disabled(isLoading)
    }

    // ランタイムパラメータセクション
    private var runtimeParamsSection: some View {
        HStack(spacing: 12) {
            Picker("Runtime Params", selection: $runtimeMode) {
                Text("Use recommended").tag(LLMRuntimeMode.auto)
                Text("Override").tag(LLMRuntimeMode.cpuOnly)
            }
            .pickerStyle(.radioGroup)
            .onChange(of: runtimeMode) { oldValue, newValue in
                ModelManager.shared.setRuntimeMode(newValue)
                if newValue == .auto { recommendedReady = true }
            }
            .accessibilityLabel(Text("Runtime parameters mode"))

            Button("Reset") {
                ModelManager.shared.resetToRecommended()
                runtimeMode = .auto
                recommendedReady = true
            }
            .disabled(runtimeMode != .cpuOnly)
            .keyboardShortcut(.init("r"), modifiers: [.command])
            .accessibilityLabel(Text("Reset to recommended parameters"))
        }
    }

    // LLMプリセットピッカー
    private var llmPresetPicker: some View {
        Picker("LLM Preset", selection: $selectedLLMPreset) {
            ForEach(availableLLMPresets, id: \.self) { p in
                Text(p)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal)
        .onChange(of: selectedLLMPreset) { oldValue, newValue in
            ModelManager.shared.setLLMPreset(name: newValue)
        }
        .disabled(isLoading)
    }

    // RAGpackアップロードセクション
    private var ragpackUploadSection: some View {
        HStack {
            Text("RAGpack(.zip) Upload:")
                .font(.title3)
                .bold()
            Spacer()
            Button(action: {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [UTType.zip]
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                if panel.runModal() == .OK {
                    documentManager.importDocument(file: panel.url!)
                }
            }) {
                Text("Choose File")
                    .font(.title3)
            }
            .disabled(isLoading)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal)
    }

    // 質問入力セクション
    private var questionInputSection: some View {
        VStack(spacing: 12) {
            TextField("Enter your question", text: $question)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .onSubmit {
                    Task { await askRAG() }
                }
                .disabled(isLoading)

            Button(action: { Task { await askRAG() } }) {
                Text("Ask")
            }
            .disabled(question.isEmpty || isLoading)
            .padding(.horizontal)

            if isLoading {
                ProgressView().padding()
            }

            Text(answer)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
        }
    }

    // ローディングオーバーレイ
    private var loadingOverlay: some View {
        Group {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.05).ignoresSafeArea()
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Generating...")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
        }
    }

    func askRAG() async {
        let _log = SystemLog()
        let _t0 = Date()
        _log.logEvent(event: "[UI] askRAG enter qLen=\(question.count)")
        defer {
            let dt = Date().timeIntervalSince(_t0)
            _log.logEvent(event: String(format: "[UI] askRAG exit (%.2f ms)", dt*1000))
        }
        guard !question.isEmpty else { return }
        guard !isLoading else { return }
        isLoading = true
        answer = ""
        // Call actual RAG inference via ModelManager
        let result = await ModelManager.shared.generateAsyncAnswer(question: question)
        answer = result
        isLoading = false

        // Build citations mapping from answer text and last retrieved chunks
        var perParagraph = CitationExtractor.extractParagraphLabels(from: result)
        let chunks = ModelManager.shared.lastRetrievedChunks
        // Fallback: if no labels found but we have sources, attach all sources to first paragraph
        let hasAnyLabel = perParagraph.contains { !$0.isEmpty }
        if !hasAnyLabel && !chunks.isEmpty {
            perParagraph = [Array(1...chunks.count)]
        }
        // Build catalog with 1-based index
        let catalog: [CitationInfo] = chunks.enumerated().map { (i, ch) in
            CitationInfo(index: i + 1, title: ch.sourceTitle, path: ch.sourcePath, page: ch.page)
        }
        let paraCitations = ParagraphCitations(perParagraph: perParagraph, catalog: catalog)

        let newQAPair = QAPair(id: UUID(), question: question, answer: answer, citations: paraCitations)
        // Cache: store QA context for potential thumbs-up capture
        let embedder = EmbeddingModel(name: "nomic-embed-text") // デフォルトの埋め込みモデル
        QAContextStore.shared.put(qaId: newQAPair.id, question: newQAPair.question, answer: newQAPair.answer, sources: chunks, embedder: embedder)
        qaHistory.append(newQAPair)
        selectedQAPair = newQAPair
        question = ""
        answer = ""
    }
}

struct HistoryView: View {
    @ObservedObject var documentManager: DocumentManager
    var body: some View {
        VStack(alignment: .leading) {
            Text("RAGpack Upload History").font(.headline).padding()
            List(documentManager.uploadHistory, id: \.filename) { history in
                Text("\(history.filename) | \(history.timestamp) | Chunks: \(history.chunkCount)")
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct RAGpackManagerView: View {
    @ObservedObject var documentManager: DocumentManager
    var body: some View {
        VStack(alignment: .leading) {
            Text("Manage RAGpack").font(.headline).padding()
            List(documentManager.ragpackChunks.keys.sorted(), id: \.self) { key in
                HStack {
                    Text(key)
                    Spacer()
                    Text("Chunks: \(documentManager.ragpackChunks[key]?.count ?? 0)")
                    Button("Delete") {
                        documentManager.deleteRAGpack(named: key)
                    }
                    .disabled(false)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

// 既存: 履歴行
struct QAHistoryRow: View {
    let qa: QAPair
    let isSelected: Bool
    var body: some View {
        VStack(alignment: .leading) {
            Text(qa.question)
                .fontWeight(isSelected ? .bold : .regular)
            Text(qa.answer)
                .lineLimit(1)
                .foregroundColor(.gray)
                .font(.caption)
        }
        .tag(qa)
    }
}

#Preview {
    ContentView()
}
#endif
