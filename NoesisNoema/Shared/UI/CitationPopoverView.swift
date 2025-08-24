
// filepath: NoesisNoema/Shared/UI/CitationPopoverView.swift
// Comments: English

import SwiftUI

struct CitationPopoverView: View {
    let citations: ParagraphCitations

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Citations").font(.headline)
            if citations.perParagraph.isEmpty || citations.catalog.isEmpty {
                Text("No citations available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(citations.perParagraph.indices, id: \.self) { pidx in
                            let labels = citations.perParagraph[pidx]
                            if !labels.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Paragraph \(pidx + 1)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    ForEach(labels, id: \.self) { label in
                                        if let info = catalogInfo(for: label) {
                                            HStack(alignment: .top, spacing: 8) {
                                                Text("[\(label)]").bold().frame(width: 34, alignment: .leading)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(info.title ?? "Untitled")
                                                        .font(.callout)
                                                    HStack(spacing: 8) {
                                                        if let page = info.page { Text("p. \(page)").font(.caption).foregroundStyle(.secondary) }
                                                        if let path = info.path { Text(path).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                                    }
                                                    HStack(spacing: 8) {
                                                        if let path = info.path {
                                                            Button("Open") { openPath(path) }
                                                            Button("Copy Path") { copy(path) }
                                                        }
                                                        Button("Copy Label") { copy("[\(label)]") }
                                                    }
                                                    .font(.caption)
                                                }
                                            }
                                        } else {
                                            HStack { Text("[\(label)]").bold(); Text("Unknown source") }.font(.caption)
                                        }
                                    }
                                }
                                .padding(8)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(12)
        .frame(minWidth: 360)
    }

    private func catalogInfo(for label: Int) -> CitationInfo? {
        citations.catalog.first { $0.index == label }
    }

    private func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func openPath(_ path: String) {
        #if os(iOS)
        if let url = URL(string: path) { UIApplication.shared.open(url) }
        #else
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            NSWorkspace.shared.openFile(path)
        } else if let url = URL(string: path) {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

#Preview {
    let cat = [
        CitationInfo(index: 1, title: "Ethics", path: "/Users/me/Docs/Spinoza.pdf", page: 12),
        CitationInfo(index: 2, title: "Letters", path: nil, page: nil)
    ]
    let per = [[1,2], [2]]
    return CitationPopoverView(citations: ParagraphCitations(perParagraph: per, catalog: cat))
}
