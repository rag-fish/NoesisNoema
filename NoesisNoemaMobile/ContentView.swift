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

    @State private var showImporter = false
    @State private var showSplash = true
    @FocusState private var questionFocused: Bool

    var availableEmbeddingModels: [String] { ModelManager.shared.availableEmbeddingModels }
    var availableLLMModels: [String] { ModelManager.shared.availableLLMModels }

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                // 上段: 設定＋質問入力＋RAGpackインポート
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Picker("Embedding", selection: $selectedEmbeddingModel) {
                            ForEach(availableEmbeddingModels, id: \.self) { Text($0) }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: selectedEmbeddingModel) { oldValue, newValue in
                            ModelManager.shared.switchEmbeddingModel(name: newValue)
                        }

                        Spacer(minLength: 16)

                        Picker("LLM", selection: $selectedLLMModel) {
                            ForEach(availableLLMModels, id: \.self) { Text($0) }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: selectedLLMModel) { oldValue, newValue in
                            ModelManager.shared.switchLLMModel(name: newValue)
                        }
                    }

                    // 複数行入力: TextEditor + プレースホルダ + Rounded枠
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $question)
                            .frame(height: 88)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3))
                            )
                            .disabled(isLoading)
                            .focused($questionFocused)
                        if question.isEmpty {
                            Text("Enter your question")
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                        }
                    }

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
                .padding(.horizontal)
                // 背景タップでキーボード閉じる
                .contentShape(Rectangle())
                .onTapGesture { questionFocused = false }

                Divider()

                // 下段: 履歴リスト + 詳細（オーバーレイ方式）
                VStack(alignment: .leading, spacing: 8) {
                    Text("History").font(.headline)

                    ZStack(alignment: .bottom) {
                        // 背面: 履歴リスト（常にフル表示）
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
                        .scrollDismissesKeyboard(.immediately)
                        .disabled(documentManager.selectedQAPair != nil || isLoading)

                        // 前面: QADetailオーバーレイ
                        if let selected = documentManager.selectedQAPair {
                            QADetailView(qapair: selected, onClose: { if !isLoading { documentManager.selectedQAPair = nil } })
                                .padding(.horizontal)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .zIndex(1)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal)
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
            .disabled(isLoading)
            .overlay(
                Group {
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
                    // 起動時仮置きスプラッシュ
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
            )
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
            documentManager.addQAPair(question: question, answer: result)
            question = ""
            isLoading = false
        }
    }
}

#Preview {
    ContentView()
}
