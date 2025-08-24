// filepath: Shared/RAG/QueryIterator.swift
// Project: NoesisNoema
// File: QueryIterator.swift
// Description: Lightweight query iterator that generates simple variants for retrieval.
// License: MIT License

import Foundation

struct QueryIterator {
    struct Config {
        var maxVariants: Int = 5
        var enableStopwordDrop: Bool = true
        var enableStemmingLite: Bool = true
    }
    
    var config: Config = .init()
    
    private let stopwords: Set<String> = [
        "the","a","an","of","to","and","or","in","on","for","with","is","are",
        // 日本語の簡易ストップワード
        "の","に","は","を","が","と","で","も","へ"
    ]
    
    func variants(for rawQuery: String) -> [String] {
        let q0 = normalize(rawQuery)
        guard !q0.isEmpty else { return [] }
        var out: [String] = []
        out.append(q0)
        
        // 1) stopword drop
        if config.enableStopwordDrop {
            let dropped = q0.splitOnWords().filter { !stopwords.contains($0) }.joined(separator: " ")
            if !dropped.isEmpty && dropped != q0 { out.append(dropped) }
        }
        
        // 2) stemming-lite (very naive: remove plural 's' or 'es', common suffixes)
        if config.enableStemmingLite {
            let toks = q0.splitOnWords().map { stemLite($0) }
            let s = toks.joined(separator: " ")
            if !s.isEmpty && s != q0 { out.append(s) }
        }
        
        // 3) deduplicate & cap
        let unique = OrderedSet(out)
        return Array(unique).prefix(config.maxVariants).map { $0 }
    }
    
    private func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        let collapsed = lowered.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func stemLite(_ t: String) -> String {
        var s = t
        if s.hasSuffix("es") { s = String(s.dropLast(2)) }
        else if s.hasSuffix("s") { s = String(s.dropLast()) }
        for suf in ["ing","ed","ly"] {
            if s.hasSuffix(suf) && s.count > suf.count + 2 {
                s = String(s.dropLast(suf.count))
                break
            }
        }
        return s
    }
}

private extension String {
    func splitOnWords() -> [String] {
        let pattern = "[A-Za-z0-9一-龥ぁ-ゔァ-ヴー々〆〤_]+"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(self.startIndex..<self.endIndex, in: self)
        let matches = regex?.matches(in: self, options: [], range: range) ?? []
        return matches.compactMap { m in
            guard let r = Range(m.range, in: self) else { return nil }
            return String(self[r])
        }
    }
}

// Preserve-order set (renamed to avoid collision with LlamaBridgeTest)
struct OrderedSet<T: Hashable>: Sequence {
    private var seen = Set<T>()
    private var items: [T] = []
    init(_ input: [T]) { for e in input where !seen.contains(e) { seen.insert(e); items.append(e) } }
    func makeIterator() -> IndexingIterator<[T]> { items.makeIterator() }
}
