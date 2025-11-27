// filepath: NoesisNoema/Shared/RAG/Citations.swift
// Comments: English

import Foundation

struct CitationInfo: Codable, Hashable {
    let index: Int // 1-based label index [1], [2], ...
    let title: String?
    let path: String?
    let page: Int?
}

struct ParagraphCitations: Codable, Hashable {
    /// paragraph index (0-based) to citation label indexes
    let perParagraph: [[Int]]
    /// catalog of citation infos (by index)
    let catalog: [CitationInfo]
}

enum CitationExtractor {
    /// Extracts paragraph-wise citation indices from the answer text.
    /// - Returns: per-paragraph arrays of 1-based label numbers
    static func extractParagraphLabels(from answer: String) -> [[Int]] {
        let paragraphs = splitParagraphs(answer)
        let regex = try! NSRegularExpression(pattern: "\\[(\\d+)\\]", options: [])
        return paragraphs.map { p in
            let ns = p as NSString
            let matches = regex.matches(in: p, options: [], range: NSRange(location: 0, length: ns.length))
            var nums: [Int] = []
            for m in matches {
                if m.numberOfRanges > 1 {
                    let g = ns.substring(with: m.range(at: 1))
                    if let n = Int(g) { nums.append(n) }
                }
            }
            // de-duplicate while preserving order
            var seen = Set<Int>()
            return nums.filter { seen.insert($0).inserted }
        }
    }
    static func splitParagraphs(_ text: String) -> [String] {
        // Normalize runs of 2+ newlines to exactly two, then split safely on string
        let normalized = text.replacingOccurrences(of: "\\n{2,}", with: "\n\n", options: .regularExpression)
        let parts = normalized.components(separatedBy: "\n\n")
        return parts.map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
