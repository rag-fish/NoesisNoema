#if os(macOS)
//  ContentView.swift
//  NoesisNoema
//
//  Created by Раскольников on 2025/07/18.

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
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

    let availableEmbeddingModels = ModelManager.shared.availableEmbeddingModels
    let availableLLMModels = ModelManager.shared.availableLLMModels
    // 新規: プリセット候補
    let availableLLMPresets = ModelManager.shared.availableLLMPresets

    var body: some View {
        NavigationSplitView {
            // Sidebar — 自動で Liquid Glass 外観
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
                .background(.regularMaterial) // 強度アップ

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
                .scrollContentBackground(.hidden) // 背景拡張
            }
            .background(.regularMaterial) // サイドバー全面ガラス
            .navigationTitle("Noesis Noema")
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 360)
        } detail: {
            // Detail — エッジトゥエッジ + Material
            Group {
                if let selected = selectedQAPair {
                    QADetailView(qapair: selected, onClose: { if !isLoading { selectedQAPair = nil } })
                        .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
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

                            Picker("LLM Model", selection: $selectedLLMModel) {
                                ForEach(availableLLMModels, id: \.self) { model in
                                    Text(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(.horizontal)
                            .onChange(of: selectedLLMModel) { oldValue, newValue in
                                ModelManager.shared.switchLLMModel(name: newValue)
                                // モデル連動: プリセットはautoへ戻す
                                selectedLLMPreset = "auto"
                                ModelManager.shared.setLLMPreset(name: "auto")
                            }
                            .disabled(isLoading)

                            // 新規: LLM Preset
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

                            // RAGpack(.zip) upload UI
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

                            // Answer
                            Text(answer)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                        }
                        .padding(.vertical)
                    }
                    .background(.clear)
                }
            }
            .background(.ultraThinMaterial) // ディテール面に広域でガラス
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbarBackground(.regularMaterial, for: .windowToolbar) // 強度アップ
        }
        .sheet(isPresented: $showRAGpackManager) {
            RAGpackManagerView(documentManager: documentManager)
        }
        .disabled(isLoading)
        .overlay(
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
        )
    }

    func askRAG() async {
        guard !question.isEmpty else { return }
        guard !isLoading else { return }
        isLoading = true
        answer = ""
        // Call actual RAG inference via ModelManager
        let result = await ModelManager.shared.generateAsyncAnswer(question: question)
        answer = result
        isLoading = false

        let newQAPair = QAPair(id: UUID(), question: question, answer: answer)
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
