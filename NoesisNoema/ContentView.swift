//
//  ContentView.swift
//  NoesisNoema
//
//  Created by Раскольников on 2025/07/18.
//

import SwiftUI

struct ContentView: View {
    @State private var question: String = ""
    @State private var answer: String = ""
    @State private var isLoading: Bool = false
    @State private var selectedEmbeddingModel: String = "MiniLM-L6-v2"
    @State private var selectedLLMModel: String = "Phi-3-mini"
    @State private var showRAGpackManager: Bool = false
    @State private var documentManager = DocumentManager()
    
    @State private var qaHistory: [QAPair] = []
    @State private var selectedQAPair: QAPair? = nil

    let availableEmbeddingModels = ["MiniLM-L6-v2", "All-MiniLM-L12-v2"]
    let availableLLMModels = ["Phi-3-mini", "Llama-3", "Gemma-2B"]

    var body: some View {
        NavigationView {
            HStack(spacing: 0) {
                VStack {
                    HStack {
                        Button("New Question") {
                            selectedQAPair = nil
                            question = ""
                            answer = ""
                        }
                        Spacer()
                        Button("Manage RAGpack") { showRAGpackManager.toggle() }
                    }
                    .padding()

                    List(selection: $selectedQAPair) {
                        ForEach(qaHistory, id: \.id) { qa in
                            // 型推論エラー回避のため、VStackを分割
                            QAHistoryRow(qa: qa, isSelected: selectedQAPair?.id == qa.id)
                        }
                        .onDelete { indexSet in
                            qaHistory.remove(atOffsets: indexSet)
                            if let selected = selectedQAPair, !qaHistory.contains(where: { $0.id == selected.id }) {
                                selectedQAPair = nil
                            }
                        }
                    }
                    .listStyle(SidebarListStyle())
                }
                .frame(minWidth: 300, maxWidth: 350)

                Divider()

                VStack(spacing: 16) {
                    if let selected = selectedQAPair {
                        QADetailView(qapair: selected)
                    } else {
                        Picker("Embedding Model", selection: $selectedEmbeddingModel) {
                            ForEach(availableEmbeddingModels, id: \.self) { model in
                                Text(model)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .padding(.horizontal)
                        .onChange(of: selectedEmbeddingModel) { newModel in
                            ModelManager.shared.switchEmbeddingModel(name: newModel)
                        }

                        Picker("LLM Model", selection: $selectedLLMModel) {
                            ForEach(availableLLMModels, id: \.self) { model in
                                Text(model)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .padding(.horizontal)
                        .onChange(of: selectedLLMModel) { newModel in
                            ModelManager.shared.switchLLMModel(name: newModel)
                        }

                        TextField("Enter your question", text: $question)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)
                            .onSubmit {
                                Task { await askRAG() }
                            }

                        Button(action: {
                            Task { await askRAG() }
                        }) {
                            Text("Ask")
                        }
                        .disabled(question.isEmpty || isLoading)
                        .padding(.horizontal)

                        if isLoading {
                            ProgressView().padding()
                        }

                        ScrollView {
                            Text(answer)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // RAGpack(.zip) upload UI
                        HStack {
                            Text("RAGpack(.zip) Upload:")
                            Spacer()
                            Button(action: {
                                let panel = NSOpenPanel()
                                panel.allowedFileTypes = ["zip"]
                                panel.allowsMultipleSelection = false
                                panel.canChooseDirectories = false
                                if panel.runModal() == .OK {
                                    documentManager.importDocument(file: panel.url!)
                                }
                            }) {
                                Text("Choose File")
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .frame(minWidth: 500)
            }
            .sheet(isPresented: $showRAGpackManager) {
                RAGpackManagerView(documentManager: documentManager)
            }
            .navigationTitle("RAGfish × NoesisNoema")
        }
    }

    func askRAG() async {
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
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

// 新規Viewを追加
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
