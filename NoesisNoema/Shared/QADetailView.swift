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
                Text("Answer")
                    .font(.headline)
                    .foregroundColor(.secondary)
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
        }
    }
}

#Preview {
    QADetailView(qapair: QAPair(question: "What is Spinoza's first axiom?", answer: "The first axiom is that everything that exists, exists either in itself or in something else."))
}
