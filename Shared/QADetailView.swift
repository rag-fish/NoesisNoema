//
//  QADetailView.swift
//  NoesisNoema
//
//  Created by Раскольников on 2025/08/03.
//

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// A detail view that displays a single QA pair (question and answer).
/// - Parameter qapair: The question-answer pair to display.
struct QADetailView: View {
    let qapair: QAPair
    var onClose: (() -> Void)? = nil
    @State private var showCitations: Bool = false
    // Feedback UI state
    @State private var showingTagSheet: Bool = false
    @State private var pendingVerdict: FeedbackVerdict? = nil
    @State private var showSubmittedToast: Bool = false

    // Default negative reason tags
    private let negativeReasonTags: [String] = [
        "Not factual", "Hallucination", "Out of scope", "Poor retrieval",
        "Formatting", "Toxicity", "Off topic", "Other"
    ]

    var body: some View {
        ZStack(alignment: .top) {
            // 本体カード
            VStack(alignment: .leading, spacing: 16) {
                // iOS: 上部ハンドル（下スワイプで閉じる導線）
                #if os(iOS)
                HStack { Spacer() }
                    .frame(height: 8)
                    .overlay(
                        Capsule()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 36, height: 5)
                            .padding(.top, 6)
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 20).onEnded { value in
                            if value.translation.height > 60 && abs(value.translation.width) < 80 {
                                onClose?()
                            }
                        }
                    )
                #endif

                Text("Question")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(qapair.question)
                    .font(.title3)
                    .padding(.bottom, 8)
                Divider()
                HStack {
                    Text("Answer")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                    if qapair.citations != nil {
                        Button(action: { showCitations.toggle() }) {
                            Label("Citations", systemImage: "book")
                        }
                        .buttonStyle(.bordered)
                        .popover(isPresented: $showCitations, arrowEdge: .top) {
                            if let c = qapair.citations {
                                CitationPopoverView(citations: c)
                            } else {
                                Text("No citations").padding(12)
                            }
                        }
                    }
                }
                // 回答の全文表示＋選択＋コピー（最大化）
                ScrollView {
                    let answerText = qapair.answer
                    Text(answerText)
                        .textSelection(.enabled)
                        .font(.body)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contextMenu {
                            Button("Copy Answer") {
                                #if os(iOS)
                                UIPasteboard.general.string = answerText
                                #else
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(answerText, forType: .string)
                                #endif
                            }
                        }
                }
                .scrollIndicators(.visible)
                .frame(maxHeight: .infinity)
                .layoutPriority(1)

                // Feedback row
                HStack(spacing: 12) {
                    Text("Feedback:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        submitFeedback(verdict: .up, tags: [])
                    } label: {
                        Label("Good", systemImage: "hand.thumbsup")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        pendingVerdict = .down
                        showingTagSheet = true
                    } label: {
                        Label("Bad", systemImage: "hand.thumbsdown")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
                .padding(.top, 4)

                if let date = qapair.date {
                    Text("Answered at: \(date.formatted(.dateTime))")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.top, 8)
                }
            }
            .padding()
            .background(
                .thinMaterial,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
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

            // 右上のクローズボタン
            if onClose != nil {
                HStack { Spacer() }
                    .overlay(
                        Button(action: { onClose?() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)
                                .accessibilityLabel("Close")
                        }
                        .buttonStyle(.plain)
                        .padding(8), alignment: .topTrailing
                    )
            }

            // Submitted toast
            if showSubmittedToast {
                VStack {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Feedback submitted")
                            .font(.footnote)
                            .foregroundStyle(.primary)
                    }
                    .padding(8)
                    .background(.ultraThickMaterial, in: Capsule())
                    Spacer()
                }
                .padding(.top, 12)
            }
        }
    }

    private func submitFeedback(verdict: FeedbackVerdict, tags: [String]) {
        let rec = FeedbackRecord(
            id: UUID(),
            qaId: qapair.id,
            question: qapair.question,
            verdict: verdict,
            tags: tags,
            timestamp: Date()
        )
        FeedbackStore.shared.save(rec)
        RewardBus.shared.publish(qaId: qapair.id, verdict: verdict, tags: tags)
        // Light confirmation toast
        withAnimation { showSubmittedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showSubmittedToast = false }
        }
        // Optional: haptics on iOS
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

#Preview {
    QADetailView(qapair: QAPair(question: "What is Spinoza's first axiom?", answer: "The first axiom is that everything that exists, exists either in itself or in something else.", citations: ParagraphCitations(perParagraph: [[1],[1,2]], catalog: [CitationInfo(index: 1, title: "Ethics", path: "/tmp/ethics.pdf", page: 1), CitationInfo(index: 2, title: "Letters", path: nil, page: nil)])))
}
