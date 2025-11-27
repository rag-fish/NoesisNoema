// filepath: NoesisNoema/Shared/Feedback/FeedbackTagSheet.swift
// Description: Tag selector sheet for negative feedback reasons.

import SwiftUI

struct FeedbackTagSheet: View {
    let allTags: [String]
    @State private var selected: Set<String> = []
    var onCancel: (() -> Void)?
    var onSubmit: (([String]) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select reasons").font(.headline)
            WrapTags(tags: allTags, selected: $selected)
                .padding(.vertical, 6)
            HStack {
                Spacer()
                Button("Cancel") { onCancel?() }
                Button("Submit") {
                    onSubmit?(Array(selected))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 360)
    }
}

private struct WrapTags: View {
    let tags: [String]
    @Binding var selected: Set<String>
    var body: some View {
        // macOSのシート内でのレイアウト崩れを避けるため、LazyVGridのadaptive列でフロー表示に変更
        ScrollView {
            let columns = [GridItem(.adaptive(minimum: 96, maximum: 180), spacing: 8, alignment: .leading)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    let isOn = selected.contains(tag)
                    TagChip(tag: tag, isOn: isOn) { toggle(tag) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }
    private func toggle(_ t: String) { if selected.contains(t) { selected.remove(t) } else { selected.insert(t) } }
}

private struct TagChip: View {
    let tag: String
    let isOn: Bool
    let onTap: () -> Void
    var body: some View {
        Text(tag)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isOn ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
            .onTapGesture { onTap() }
            .help("Toggle tag: \(tag)")
    }
}
