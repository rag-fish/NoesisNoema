//
//  QADetailView.swift
//  NoesisNoema
//
//  Created by Раскольников on 2025/08/03.
//

import SwiftUI

/// A detail view that displays a single QA pair (question and answer).
/// - Parameter qapair: The question-answer pair to display.
struct QADetailView: View {
    let qapair: QAPair

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            Text(qapair.answer)
                .font(.body)
                .padding(.bottom, 8)
            Spacer()
            Text("Answered at: \(qapair.date?.formatted(.dateTime))")
                .font(.footnote)
                .foregroundColor(.gray)
                .padding(.top, 16)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

#Preview {
    QADetailView(qapair: QAPair(question: "What is Spinoza's first axiom?", answer: "The first axiom is that everything that exists, exists either in itself or in something else."))
}
