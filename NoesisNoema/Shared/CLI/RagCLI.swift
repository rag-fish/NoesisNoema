// filepath: /Users/raskolnikoff/Documents/Xcode Projects/NoesisNoema/NoesisNoema/Shared/RagCLI.swift
// Project: NoesisNoema
// File: RagCLI.swift
// Description: CLI interface for RAG retrieval using LocalRetriever (BM25+Embedding → Query iteration → MMR)
// License: MIT License

import Foundation

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
    
    private static func printUsage() {
        print("""
        NoesisNoema RAG CLI
        
        Usage: nn rag <command> [options]
        
        Commands:
          retrieve "<query>"    Retrieve top-k chunks via BM25+Embedding → MMR
          demo [query]           Seed a demo corpus and run a traced retrieval
          help                   Show this help
        
        Options (retrieve):
          --top-k N              Number of final results (default: 5)
          --lambda F             MMR trade-off (0..1, default: 0.7)
          --trace                Log decisions and intermediate stats
        
        Examples:
          nn rag retrieve "explain bm25 and mmr" --top-k 5 --trace
          nn rag demo "apple silicon unified memory"
        """)
    }
}
