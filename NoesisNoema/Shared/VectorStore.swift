//// VectorStore.swift
/// //  NoesisNoema
/// //  Created by Раскольников on 2025/07/18.


import Foundation

class VectorStore {
    
    /**
        A structure representing a chunk of text with its embedding.
        - `text`: The text content of the chunk.
        - `embedding`: The embedding vector for the text.
        - `metadata`: Optional metadata associated with the chunk.
     */
    var chunks: [Chunk]
    var embeddingModel: EmbeddingModel
    var isEmbedded: Bool
    /// Initializes a VectorStore with an embedding model and an optional initial set of chunks.
    /// - Parameters:
    ///  - embeddingModel: The model used to generate embeddings for text.
    init(embeddingModel: EmbeddingModel, chunks: [Chunk] = []) {
        self.embeddingModel = embeddingModel
        self.chunks = chunks
        self.isEmbedded = false
    }
    
    // MARK: - CRUD / Utilities
    /// 総チャンク数
    var count: Int { chunks.count }
    
    /// 生テキスト群を受け取り、埋め込みを生成して追加（重複はcontent+embeddingで排除）
    func addTexts(_ texts: [String], deduplicate: Bool = true) {
        guard !texts.isEmpty else { return }
        var newChunks: [Chunk] = []
        newChunks.reserveCapacity(texts.count)
        for t in texts {
            let emb = embeddingModel.embed(text: t)
            newChunks.append(Chunk(content: t, embedding: emb))
        }
        addChunks(newChunks, deduplicate: deduplicate)
    }
    
    /// 既存のChunk配列を追加（必要なら重複除外）
    func addChunks(_ newChunks: [Chunk], deduplicate: Bool = true) {
        guard !newChunks.isEmpty else { return }
        if !deduplicate {
            chunks.append(contentsOf: newChunks)
            return
        }
        let existing = chunks
        // content と embedding 完全一致で重複判定
        let uniques = newChunks.filter { nc in
            !existing.contains { ec in ec.content == nc.content && ec.embedding == nc.embedding }
        }
        if !uniques.isEmpty {
            chunks.append(contentsOf: uniques)
        }
    }
    
    /// 全削除
    func clear() { chunks.removeAll() }
    
    /// すべてのチャンクを現行のEmbeddingModelで再埋め込み（contentは保持）
    func reembedAll() {
        guard !chunks.isEmpty else { return }
        for i in chunks.indices {
            chunks[i].embedding = embeddingModel.embed(text: chunks[i].content)
        }
    }
    
    /// JSONファイルへ保存（ChunkはCodable）
    func save(to url: URL) throws {
        let data = try JSONEncoder().encode(chunks)
        try data.write(to: url, options: .atomic)
    }
    
    /// JSONファイルから読込（既存は置き換え）
    func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let loaded = try JSONDecoder().decode([Chunk].self, from: data)
        self.chunks = loaded
    }
        
    /**
        クエリ埋め込みベクトルに最も類似したChunkを返す
        - Parameter queryEmbedding: クエリの埋め込みベクトル（[Float]型）
        - Returns: 類似度上位のChunk配列
     */
    func findRelevant(queryEmbedding: [Float], topK: Int = 3) -> [Chunk] {
        guard !chunks.isEmpty else { return [] }
        // 長さが一致しない場合は安全フォールバックとして先頭から返す
        let dim = queryEmbedding.count
        guard dim > 0 else { return [] }
        var scored: [(Chunk, Float)] = []
        scored.reserveCapacity(chunks.count)
        for c in chunks {
            if c.embedding.count == dim {
                let s = cosineSimilarity(a: queryEmbedding, b: c.embedding)
                scored.append((c, s))
            }
        }
        if scored.isEmpty {
            return Array(chunks.prefix(topK))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(topK).map { $0.0 }
    }
    
    private func cosineSimilarity(a: [Float], b: [Float]) -> Float {
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        let n = min(a.count, b.count)
        var i = 0
        while i < n {
            let x = a[i]
            let y = b[i]
            dot += x * y
            na += x * x
            nb += y * y
            i += 1
        }
        let denom = (sqrtf(max(na, 1e-9)) * sqrtf(max(nb, 1e-9)))
        if denom == 0 { return 0 }
        return dot / denom
    }
    
    /// Retrieves the top-K most relevant chunks for a given query string using the embedding model.
    /// - Parameters:
    ///   - query: The query string to search for relevant chunks.
    ///   - topK: The number of top relevant chunks to retrieve (default: 3).
    /// - Returns: An array of the most relevant chunks.
    public func retrieveChunks(for query: String, topK: Int = 3) -> [Chunk] {
        // Generate query embedding using the embedding model
        let queryEmbedding = embeddingModel.embed(text: query)
        // Retrieve top-K relevant chunks
        let relevantChunks = findRelevant(queryEmbedding: queryEmbedding, topK: topK)
        return relevantChunks
    }
    
    /// Generates a RAG (Retrieval-Augmented Generation) answer for the given query.
    /// - Parameters:
    ///   - query: The question/query string.
    ///   - topK: The number of top relevant chunks to retrieve (default: 3).
    /// - Returns: The answer string generated by the LLM.
    public func ragAnswer(for query: String, topK: Int = 3) -> String {
        // Retrieve relevant chunks for the query
        let relevantChunks = retrieveChunks(for: query, topK: topK)
        // Concatenate their contents to form the context string
        var context = relevantChunks.map { $0.content }.joined(separator: "\n---\n")
        // 軽いトリムと安全上限
        context = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if context.count > 2000 { context = String(context.prefix(2000)) }
        // LLMへ文脈を注入して生成
        let model = ModelManager.shared.currentLLMModel
        let ctx = context.isEmpty ? nil : context
        let answer = model.generate(prompt: query, context: ctx)
        return answer
    }
    
    /// VectorStoreのシングルトン（RAG検索対象チャンクを保持）
    static let shared = VectorStore(embeddingModel: EmbeddingModel(name: "default-embedding"))
}
