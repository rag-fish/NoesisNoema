//
//  DesktopHistoryView.swift
//  NoesisNoema (macOS)
//
//  ADR-0010 History section. A two-pane browser: the Q&A archive list (left)
//  and a detail pane (right) showing the question, answer, retrieved citations,
//  and 👍/👎 feedback. Feedback is wired to `FeedbackStore.save(...)` and
//  `RewardBus.publish(...)`, identical to the iOS HistoryDetailSheet flow
//  (PR #87) — written fresh for macOS (HSplitView, NSColor backgrounds, a
//  native reason Menu instead of a sheet).
//
//  Citations come from `QAContextStore` (populated by DesktopChatView at ask
//  time from `NoemaResponse.sources`) — the same per-QA context the feedback
//  cache uses.
//

#if os(macOS)
import SwiftUI

struct DesktopHistoryView: View {
    @ObservedObject var documentManager: DocumentManager
    @ObservedObject private var modelManager = ModelManager.shared

    @State private var selectedID: UUID?

    private var selectedQA: QAPair? {
        guard let id = selectedID else { return nil }
        return documentManager.qaHistory.first { $0.id == id }
    }

    var body: some View {
        HSplitView {
            historyList
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 380)

            Group {
                if let qa = selectedQA {
                    DesktopQADetail(qa: qa, modelName: modelManager.currentLLMModel.name)
                } else {
                    detailPlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("History")
    }

    // MARK: - List

    @ViewBuilder
    private var historyList: some View {
        if documentManager.qaHistory.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clock")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No History Yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Your Q&A history will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        } else {
            List(selection: $selectedID) {
                ForEach(documentManager.qaHistory) { qa in
                    DesktopHistoryRow(qa: qa, modelName: modelManager.currentLLMModel.name)
                        .tag(qa.id)
                }
            }
            .listStyle(.inset)
        }
    }

    private var detailPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Select a question to see its answer and citations.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Row

private struct DesktopHistoryRow: View {
    let qa: QAPair
    let modelName: String

    private var formattedDate: String {
        guard let date = qa.date else { return "Unknown time" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(qa.question)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(formattedDate)
                Text("•")
                Text(modelName).lineLimit(1)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail

private struct DesktopQADetail: View {
    let qa: QAPair
    let modelName: String

    @State private var showSubmittedToast: Bool = false

    private let negativeReasonTags: [String] = [
        "Not factual", "Hallucination", "Out of scope", "Poor retrieval",
        "Formatting", "Toxicity", "Off topic", "Other"
    ]

    /// Citations recorded for this Q&A at ask time (from NoemaResponse.sources).
    private var sources: [Chunk] {
        QAContextStore.shared.get(qa.id)?.sources ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section(title: "Question") {
                    Text(qa.question)
                        .font(.system(size: 15, weight: .medium))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                section(title: "Answer") {
                    Text(qa.answer)
                        .font(.system(size: 14))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                citationsSection

                Divider()

                feedbackSection

                if let date = qa.date {
                    Text("Answered \(date.formatted(.dateTime)) · \(modelName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .overlay(alignment: .top) { submittedToast }
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private var citationsSection: some View {
        section(title: "Citations") {
            if sources.isEmpty {
                Text("No citations recorded for this answer.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(sources.enumerated()), id: \.offset) { index, chunk in
                        DesktopCitationRow(index: index + 1, chunk: chunk)
                    }
                }
            }
        }
    }

    private var feedbackSection: some View {
        section(title: "Feedback") {
            HStack(spacing: 12) {
                Button {
                    submitFeedback(verdict: .up, tags: [])
                } label: {
                    Label("Good", systemImage: "hand.thumbsup.fill")
                }
                .buttonStyle(.bordered)
                .tint(.green)

                Menu {
                    ForEach(negativeReasonTags, id: \.self) { tag in
                        Button(tag) { submitFeedback(verdict: .down, tags: [tag]) }
                    }
                    Divider()
                    Button("Bad (no reason)") { submitFeedback(verdict: .down, tags: []) }
                } label: {
                    Label("Bad", systemImage: "hand.thumbsdown.fill")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .tint(.red)
            }
        }
    }

    @ViewBuilder
    private var submittedToast: some View {
        if showSubmittedToast {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Feedback submitted")
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func submitFeedback(verdict: FeedbackVerdict, tags: [String]) {
        let record = FeedbackRecord(
            id: UUID(),
            qaId: qa.id,
            question: qa.question,
            verdict: verdict,
            tags: tags,
            timestamp: Date()
        )
        FeedbackStore.shared.save(record)
        RewardBus.shared.publish(qaId: qa.id, verdict: verdict, tags: tags)

        withAnimation { showSubmittedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showSubmittedToast = false }
        }
    }
}

// MARK: - Citation row

private struct DesktopCitationRow: View {
    let index: Int
    let chunk: Chunk

    private var title: String {
        chunk.sourceTitle ?? chunk.sourcePath ?? "Source \(index)"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("[\(index)]")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if let page = chunk.page {
                        Text("p.\(page)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(chunk.content)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    DesktopHistoryView(documentManager: DocumentManager())
        .frame(width: 720, height: 500)
}
#endif
