//
//  ChatView.swift
//  NoesisNoemaMobile
//
//  Created by Раскольников on 2025/11/27.
//

import SwiftUI

// MARK: - ChatScreen (Full-Screen Container)
struct ChatScreen: View {
    @ObservedObject var documentManager: DocumentManager
    @ObservedObject private var modelManager = ModelManager.shared

    @State private var question: String = ""
    @State private var isLoading: Bool = false
    @FocusState private var questionFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderView(
                modelName: modelManager.currentLLMModel.name,
                presetName: modelManager.currentLLMPreset
            )

            contentArea

            ChatInputBar(
                question: $question,
                isLoading: isLoading,
                questionFocused: $questionFocused,
                onSubmit: startAsk
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(Color(.systemBackground))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .overlay(loadingOverlay)
    }

    private var contentArea: some View {
        Group {
            if documentManager.qaHistory.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Ask me anything.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
            } else {
                // Chat tab: Show only the latest QA (most recent)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let latestQA = documentManager.qaHistory.last {
                            MessageRow(qa: latestQA)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: CGFloat.infinity, alignment: .topLeading)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if isLoading {
            ZStack {
                Color.black.opacity(0.05)
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Generating...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .allowsHitTesting(true)
            .transition(.opacity)
        }
    }

    private func startAsk() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isLoading else { return }
        question = trimmed
        questionFocused = false
        isLoading = true

        // PERFORMANCE: Run entire RAG pipeline off main thread
        Task.detached(priority: .userInitiated) {
            let result = await ModelManager.shared.generateAsyncAnswer(question: trimmed)

            await MainActor.run {
                let newPair = documentManager.addQAPair(question: trimmed, answer: result)
                Task {
                    let sources = await MainActor.run { ModelManager.shared.lastRetrievedChunks }
                    let embedder = await MainActor.run { ModelManager.shared.currentEmbeddingModel }
                    QAContextStore.shared.put(qaId: newPair.id, question: newPair.question, answer: newPair.answer, sources: sources, embedder: embedder)
                }
                question = ""
                isLoading = false
            }
        }
    }
}

// MARK: - ChatView (Wrapper)
struct ChatView: View {
    @ObservedObject var documentManager: DocumentManager

    var body: some View {
        ChatScreen(documentManager: documentManager)
    }
}

// MARK: - Chat Header View
struct ChatHeaderView: View {
    let modelName: String
    let presetName: String

    private let headerHeight: CGFloat = 80

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image("huss_1926_bg")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: headerHeight)
                .clipped()
                .opacity(0.30)
                .blur(radius: 1.5)

            VStack(alignment: .leading, spacing: 4) {
                Text("Noesis Noema")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)

                Text("Model: \(modelName) · Preset: \(presetName)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(height: headerHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
    }
}



// MARK: - Chat Input Bar
struct ChatInputBar: View {
    @Binding var question: String
    let isLoading: Bool
    @FocusState.Binding var questionFocused: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Type your question…", text: $question)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color.white)
                .overlay(
                    Rectangle()
                        .stroke(Color(hex: "#DADADA"), lineWidth: 1)
                )
                .focused($questionFocused)
                .disabled(isLoading)
                .onSubmit(onSubmit)

            Button(action: onSubmit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16))
                    .foregroundColor(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading ? .secondary : .accentColor)
            }
            .frame(width: 32, height: 32)
            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
        }
        .background(Color.white)
    }
}

// MARK: - Message Row Component
struct MessageRow: View {
    let qa: QAPair

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Text(qa.question)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .frame(maxWidth: CGFloat.infinity, alignment: .leading)
            .background(Color(.systemGray6))

            HStack(alignment: .top, spacing: 0) {
                Text(qa.answer)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .frame(maxWidth: CGFloat.infinity, alignment: .leading)
            .background(Color(hex: "#FAFAFA"))
        }
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ChatView(documentManager: DocumentManager())
}
