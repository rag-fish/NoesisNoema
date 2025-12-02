//
//  HistoryView.swift
//  NoesisNoemaMobile
//
//  Created by Раскольников on 2025/11/27.
//

import SwiftUI

struct HistoryView: View {
    @ObservedObject var documentManager: DocumentManager
    @ObservedObject private var modelManager = ModelManager.shared
    @State private var selectedQA: QAPair? = nil
    @State private var showDetailSheet: Bool = false

    var body: some View {
        ScrollView {
            if documentManager.qaHistory.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No History Yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Your Q&A history will appear here")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: CGFloat.infinity, minHeight: 200)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(documentManager.qaHistory) { qa in
                        HistoryRowView(qa: qa, modelName: modelManager.currentLLMModel.name)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedQA = qa
                                showDetailSheet = true
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
        }
        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
        .background(Color.white)
        .sheet(isPresented: $showDetailSheet) {
            if let qa = selectedQA {
                HistoryDetailSheet(qa: qa)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

// MARK: - History Row View
struct HistoryRowView: View {
    let qa: QAPair
    let modelName: String

    private var formattedDate: String {
        if let date = qa.date {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: date, relativeTo: Date())
        }
        return "Unknown time"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(qa.question)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(formattedDate)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                Text("•")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                Text(modelName)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - History Detail Sheet
struct HistoryDetailSheet: View {
    let qa: QAPair
    @Environment(\.dismiss) private var dismiss
    @State private var showingTagSheet: Bool = false
    @State private var pendingVerdict: FeedbackVerdict? = nil
    @State private var showSubmittedToast: Bool = false

    private let negativeReasonTags: [String] = [
        "Not factual", "Hallucination", "Out of scope", "Poor retrieval",
        "Formatting", "Toxicity", "Off topic", "Other"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Custom header bar
            HStack {
                Text("Q&A Details")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(.systemBackground))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Question")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        Text(qa.question)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Answer")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        Text(qa.answer)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Feedback")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        HStack(spacing: 12) {
                            Button {
                                submitFeedback(verdict: .up, tags: [])
                            } label: {
                                Label("Good", systemImage: "hand.thumbsup.fill")
                                    .font(.system(size: 15))
                            }
                            .buttonStyle(.bordered)
                            .tint(.green)

                            Button {
                                pendingVerdict = .down
                                showingTagSheet = true
                            } label: {
                                Label("Bad", systemImage: "hand.thumbsdown.fill")
                                    .font(.system(size: 15))
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }

                    if let date = qa.date {
                        Text("Answered at: \(date.formatted(.dateTime))")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
        }
        .overlay(submittedToast, alignment: .top)
        .sheet(isPresented: $showingTagSheet) {
            FeedbackTagSheet(allTags: negativeReasonTags, onCancel: {
                showingTagSheet = false
                pendingVerdict = nil
            }, onSubmit: { tags in
                showingTagSheet = false
                if let v = pendingVerdict { submitFeedback(verdict: v, tags: tags) }
                pendingVerdict = nil
            })
        }
    }

    @ViewBuilder
    private var submittedToast: some View {
        if showSubmittedToast {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Feedback submitted")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThickMaterial, in: Capsule())
            .padding(.top, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func submitFeedback(verdict: FeedbackVerdict, tags: [String]) {
        let rec = FeedbackRecord(
            id: UUID(),
            qaId: qa.id,
            question: qa.question,
            verdict: verdict,
            tags: tags,
            timestamp: Date()
        )
        FeedbackStore.shared.save(rec)
        RewardBus.shared.publish(qaId: qa.id, verdict: verdict, tags: tags)

        withAnimation { showSubmittedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showSubmittedToast = false }
        }
    }
}

#Preview {
    HistoryView(documentManager: DocumentManager())
}
