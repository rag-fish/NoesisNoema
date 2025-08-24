// filepath: Shared/CLI/RagCLI.swift
// Project: NoesisNoema
// File: RagCLI.swift
// Description: CLI interface for RAG retrieval using LocalRetriever (BM25+Embedding → Query iteration → MMR)
// License: MIT License

import Foundation

#if BRIDGE_TEST
// Minimal DeepSearch for CLI builds (LlamaBridgeTest) in case the shared file is not included in the target
private struct _CLI_DeepSearch {
    struct Config {
        var rounds: Int = 2
        var breadth: Int = 8
        var topK: Int = 5
        var mmrLambda: Float = 0.7
        var enableQueryIteration: Bool = true
        var trace: Bool = false
    }
    var config: Config = .init()
    private let store: VectorStore
    private var retriever: LocalRetriever
    init(store: VectorStore = .shared, config: Config = .init()) {
        self.store = store
        self.config = config
        var rcfg = LocalRetriever.Config()
        rcfg.stageCandidates = max(config.breadth, rcfg.stageCandidates)
        rcfg.topK = max(config.topK, 1)
        rcfg.mmrLambda = config.mmrLambda
        rcfg.enableQueryIteration = config.enableQueryIteration
        self.retriever = LocalRetriever(store: store, config: rcfg)
    }
    func retrieve(query: String) -> [Chunk] {
        let base = retriever.retrieve(query: query, k: config.breadth, lambda: config.mmrLambda, trace: config.trace)
        guard !base.isEmpty else { return [] }
        // Simple expansion: take top terms from first few chunks
        var pool = base
        var seen = Set(pool.map { $0.content })
        let terms = topTerms(from: base)
        for t in terms.prefix(6) {
            let cand = retriever.retrieve(query: t, k: config.breadth, lambda: config.mmrLambda, trace: config.trace)
            for c in cand where seen.insert(c.content).inserted { pool.append(c) }
        }
        let qEmb = store.embeddingModel.embed(text: query)
        return MMR.rerank(queryEmbedding: qEmb, candidates: pool, k: config.topK, lambda: config.mmrLambda, trace: config.trace)
    }
    private func topTerms(from chunks: [Chunk]) -> [String] {
        var freq: [String:Int] = [:]
        for c in chunks.prefix(config.breadth) {
            let toks = tokenize(c.content)
            for t in Set(toks) { if t.count >= 3 { freq[t, default: 0] += 1 } }
        }
        return freq.sorted { $0.value > $1.value }.map { $0.key }
    }
    private func tokenize(_ s: String) -> [String] {
        let lowered = s.lowercased()
        let pattern = "[A-Za-z0-9一-龥ぁ-ゔァ-ヴー々〆〤_]+"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
        let matches = regex?.matches(in: lowered, options: [], range: range) ?? []
        return matches.compactMap { m in
            guard let r = Range(m.range, in: lowered) else { return nil }
            return String(lowered[r])
        }
    }
}
// Typealias to keep CLI code unchanged
private typealias DeepSearch = _CLI_DeepSearch
#endif

struct RagCLI {
    static func handleCommand(_ args: [String]) async -> Int {
        guard args.count >= 2 else {
            printUsage()
            return 1
        }
        let command = args[1].lowercased()
        switch command {
        case "retrieve":
            return handleRetrieve(Array(args.dropFirst(2)))
        case "deep":
            return handleDeep(Array(args.dropFirst(2)))
        case "eval":
            return handleEval(Array(args.dropFirst(2)))
        case "demo":
            return handleDemo(Array(args.dropFirst(2)))
        case "help", "-h", "--help":
            printUsage(); return 0
        default:
            print("Unknown rag command: \(command)")
            printUsage(); return 1
        }
    }
    
    private static func handleRetrieve(_ args: [String]) -> Int {
        var query: String?
        var topK = 5
        var lambda: Float = 0.7
        var trace = false
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "--top-k", i+1 < args.count, let v = Int(args[i+1]) { topK = v; i += 2; continue }
            if a == "--lambda", i+1 < args.count, let v = Float(args[i+1]) { lambda = v; i += 2; continue }
            if a == "--trace" { trace = true; i += 1; continue }
            if !a.hasPrefix("-") && query == nil { query = a; i += 1; continue }
            i += 1
        }
        guard let q = query, !q.isEmpty else {
            print("Usage: nn rag retrieve \"<query>\" [--top-k N] [--lambda 0.7] [--trace]")
            return 1
        }
        let retriever = LocalRetriever(store: .shared)
        let results = retriever.retrieve(query: q, k: topK, lambda: lambda, trace: trace)
        if results.isEmpty {
            print("No results. VectorStore is empty or no matches found.")
            return 0
        }
        print("Top \(min(topK, results.count)) results:")
        for (idx, c) in results.enumerated() {
            let preview = c.content.replacingOccurrences(of: "\n", with: " ")
            let p = preview.count > 200 ? String(preview.prefix(200)) + "…" : preview
            print(String(format: "%2d. %@", idx+1, p))
        }
        return 0
    }

    private static func handleDeep(_ args: [String]) -> Int {
        var query: String?
        var topK = 5
        var rounds = 2
        var breadth = 8
        var lambda: Float = 0.7
        var trace = false
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "--top-k", i+1 < args.count, let v = Int(args[i+1]) { topK = v; i += 2; continue }
            if a == "--rounds", i+1 < args.count, let v = Int(args[i+1]) { rounds = v; i += 2; continue }
            if a == "--breadth", i+1 < args.count, let v = Int(args[i+1]) { breadth = v; i += 2; continue }
            if a == "--lambda", i+1 < args.count, let v = Float(args[i+1]) { lambda = v; i += 2; continue }
            if a == "--trace" { trace = true; i += 1; continue }
            if !a.hasPrefix("-") && query == nil { query = a; i += 1; continue }
            i += 1
        }
        guard let q = query, !q.isEmpty else {
            print("Usage: nn rag deep \"<query>\" [--top-k N] [--rounds R] [--breadth B] [--lambda 0.7] [--trace]")
            return 1
        }
        let cfg = DeepSearch.Config(rounds: rounds, breadth: breadth, topK: topK, mmrLambda: lambda, enableQueryIteration: true, trace: trace)
        let deep = DeepSearch(store: .shared, config: cfg)
        let results = deep.retrieve(query: q)
        if results.isEmpty {
            print("No results. VectorStore is empty or no matches found.")
            return 0
        }
        print("[DeepSearch] Top \(min(topK, results.count)) results:")
        for (idx, c) in results.enumerated() {
            let preview = c.content.replacingOccurrences(of: "\n", with: " ")
            let p = preview.count > 200 ? String(preview.prefix(200)) + "…" : preview
            print(String(format: "%2d. %@", idx+1, p))
        }
        return 0
    }
    
    private static func handleDemo(_ args: [String]) -> Int {
        // Seed a tiny demo corpus if empty
        if VectorStore.shared.count == 0 {
            let docs = [
                "Swift is a powerful and intuitive programming language for iOS and macOS.",
                "MMR stands for Maximal Marginal Relevance and balances relevance and diversity.",
                "BM25 is a ranking function used by search engines to estimate the relevance of documents.",
                "Embedding models map text into vectors so that similar texts are close in the vector space.",
                "Query iteration generates query variants to improve recall in retrieval systems.",
                "Apple Silicon like M1 and M2 provides unified memory architecture."
            ]
            VectorStore.shared.addTexts(docs)
        }
        print("Demo corpus size: \(VectorStore.shared.count)")
        let q = args.first ?? "What is MMR and BM25 in retrieval?"
        let retriever = LocalRetriever(store: .shared)
        let results = retriever.retrieve(query: q, k: 5, lambda: 0.7, trace: true)
        guard !results.isEmpty else { print("No results."); return 0 }
        print("\nContext:")
        for c in results { print("- ", c.content) }
        return 0
    }

    private static func handleEval(_ args: [String]) -> Int {
        enum Method: String { case retrieve, deep }
        var method: Method = .retrieve
        var topK = 5
        var rounds = 2
        var breadth = 8
        var lambda: Float = 0.7
        var trace = false
        var useBuiltin = true
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "--method", i+1 < args.count { method = Method(rawValue: args[i+1].lowercased()) ?? .retrieve; i += 2; continue }
            if a == "--top-k", i+1 < args.count, let v = Int(args[i+1]) { topK = v; i += 2; continue }
            if a == "--rounds", i+1 < args.count, let v = Int(args[i+1]) { rounds = v; i += 2; continue }
            if a == "--breadth", i+1 < args.count, let v = Int(args[i+1]) { breadth = v; i += 2; continue }
            if a == "--lambda", i+1 < args.count, let v = Float(args[i+1]) { lambda = v; i += 2; continue }
            if a == "--trace" { trace = true; i += 1; continue }
            if a == "--from-json" { useBuiltin = false; i += 1; continue } // reserved for future
            i += 1
        }
        // Seed demo corpus if empty
        if VectorStore.shared.count == 0 {
            let docs = [
                "Swift is a powerful and intuitive programming language for iOS and macOS.",
                "MMR stands for Maximal Marginal Relevance and balances relevance and diversity.",
                "BM25 is a ranking function used by search engines to estimate the relevance of documents.",
                "Embedding models map text into vectors so that similar texts are close in the vector space.",
                "Query iteration generates query variants to improve recall in retrieval systems.",
                "Apple Silicon like M1 and M2 provides unified memory architecture."
            ]
            VectorStore.shared.addTexts(docs)
        }
        struct EvalCase { let query: String; let expect: [String] }
        let builtin: [EvalCase] = [
            .init(query: "what is mmr", expect: ["mmr", "maximal", "relevance"]),
            .init(query: "explain bm25", expect: ["bm25", "ranking"]),
            .init(query: "what are embeddings", expect: ["embedding", "vectors", "vector space"]),
            .init(query: "query iteration", expect: ["query iteration"]),
            .init(query: "apple silicon memory", expect: ["unified", "memory", "apple silicon"])
        ]
        let cases = useBuiltin ? builtin : builtin // placeholder for future JSON

        var hits = 0
        var total = cases.count
        print("RAG Eval — method=\(method) topK=\(topK) rounds=\(rounds) breadth=\(breadth) lambda=\(lambda)")
        for (idx, ec) in cases.enumerated() {
            let results: [Chunk]
            switch method {
            case .retrieve:
                let retr = LocalRetriever(store: .shared)
                results = retr.retrieve(query: ec.query, k: topK, lambda: lambda, trace: trace)
            case .deep:
                let cfg = DeepSearch.Config(rounds: rounds, breadth: breadth, topK: topK, mmrLambda: lambda, enableQueryIteration: true, trace: trace)
                let deep = DeepSearch(store: .shared, config: cfg)
                results = deep.retrieve(query: ec.query)
            }
            let ok = results.contains { c in
                let txt = c.content.lowercased()
                return ec.expect.contains(where: { txt.contains($0.lowercased()) })
            }
            if ok { hits += 1 }
            print(String(format: "%2d. %@ — %@", idx+1, ec.query, ok ? "HIT" : "MISS"))
            if trace {
                for (j, c) in results.enumerated() { print(String(format: "   %2d) %@", j+1, c.content)) }
            }
        }
        let acc = total > 0 ? Double(hits) / Double(total) : 0
        print(String(format: "Accuracy: %.1f%%  (%d/%d)", acc*100.0, hits, total))
        return 0
    }
    
    private static func printUsage() {
        print("""
        NoesisNoema RAG CLI
        
        Usage: nn rag <command> [options]
        
        Commands:
          retrieve "<query>"    Retrieve top-k chunks via BM25+Embedding → MMR
          deep "<query>"        Multi-round DeepSearch (expansion + hybrid + MMR)
          eval [options]         Run a tiny retrieval eval on a builtin dataset
          demo [query]           Seed a demo corpus and run a traced retrieval
          help                   Show this help
        
        Options (retrieve):
          --top-k N              Number of final results (default: 5)
          --lambda F             MMR trade-off (0..1, default: 0.7)
          --trace                Log decisions and intermediate stats
        
        Options (deep):
          --top-k N              Number of final results (default: 5)
          --rounds R             Expansion rounds (default: 2)
          --breadth B            Candidates per round (default: 8)
          --lambda F             MMR trade-off (0..1, default: 0.7)
          --trace                Log decisions and intermediate stats
        
        Options (eval):
          --method retrieve|deep Select retrieval method (default: retrieve)
          --top-k N              TopK for evaluation (default: 5)
          --rounds R             Used when method=deep (default: 2)
          --breadth B            Used when method=deep (default: 8)
          --lambda F             MMR trade-off (default: 0.7)
          --trace                Print per-case results
        
        Examples:
          nn rag retrieve "explain bm25 and mmr" --top-k 5 --trace
          nn rag deep "apple silicon unified memory" --rounds 2 --breadth 10 --top-k 5 --trace
          nn rag eval --method deep --top-k 5 --rounds 2 --breadth 10 --trace
        """)
    }
}
