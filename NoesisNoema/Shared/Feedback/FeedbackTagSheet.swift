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
        FlexibleStack(spacing: 8, runSpacing: 8) {
            ForEach(tags, id: \.self) { tag in
                let isOn = selected.contains(tag)
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isOn ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12), in: Capsule())
                    .foregroundStyle(isOn ? .accent : .primary)
                    .onTapGesture { toggle(tag) }
                    .help("Toggle tag: \(tag)")
            }
        }
    }
    private func toggle(_ t: String) { if selected.contains(t) { selected.remove(t) } else { selected.insert(t) } }
}

// A simple flow layout for tags
private struct FlexibleStack<Content: View>: View {
    let spacing: CGFloat
    let runSpacing: CGFloat
    let content: Content
    init(spacing: CGFloat = 8, runSpacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.runSpacing = runSpacing
        self.content = content()
    }
    var body: some View {
        GeometryReader { geo in
            self.generateContent(in: geo)
        }
        .frame(minHeight: 10)
    }
    private func generateContent(in g: GeometryProxy) -> some View {
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        return ZStack(alignment: .topLeading) {
            content
                .alignmentGuide(.leading) { d in
                    if currentX + d.width > g.size.width {
                        currentX = 0
                        currentY -= (d.height + runSpacing)
                    }
                    let result = currentX
                    currentX += d.width + spacing
                    return result
                }
                .alignmentGuide(.top) { d in
                    let result = currentY
                    return result
                }
        }
    }
}
