// Project: NoesisNoema
// File: EmbeddingModel.swift
// Created by Раскольников on 2025/07/20.
// Description: Real semantic embedding model backed by llama.cpp (ADR-0011, PR-A).
//   Replaces the former 10-dim pseudo-hash stub — the root cause of broken RAG.
// License: MIT License

import Foundation

/// Query-side text embedder. Holds a `LlamaEmbeddingContext` and exposes a
/// synchronous `embed(text:)` (preserved from the old stub so the many sync call
/// sites compile unchanged) via a blocking bridge over the actor's async API.
///
/// nomic-embed-text-v1.5 requires task prefixes; PR-A only has query-side callers
/// so it always applies `"search_query: "`. PR-B introduces `"search_document: "`
/// for pack-side ingestion in the v1.2 RAGpackReader.
class EmbeddingModel {

    var name: String

    /// Embedder GGUF resource (git-ignored; bundled into the app target manually).
    static let embedderResourceName = "nomic-embed-text-v1.5.Q5_K_M"
    static let embedderResourceExt = "gguf"
    private static let taskPrefix = "search_query: "

    /// nil when the embedder GGUF could not be found/loaded — `embed` then logs
    /// loudly and returns []. We deliberately do NOT fatalError at init so the app
    /// still launches on a build missing the (git-ignored) GGUF; the empty vector
    /// makes the failure visible downstream rather than silently wrong.
    private let context: LlamaEmbeddingContext?

    /// Forwarded from the loaded context (0 when not loaded). PR-B needs these.
    let dimension: Int
    let modelFingerprint: String

    // PERFORMANCE: Cache embeddings to avoid recomputation. Keyed on the
    // task-prefixed text (the exact string handed to the embedder).
    private var embeddingCache: [String: [Float]] = [:]
    private let cacheQueue = DispatchQueue(label: "com.noesis.embedding.cache", attributes: .concurrent)
    private let maxCacheSize = 500

    init(name: String) {
        self.name = name
        if let path = EmbeddingModel.resolveEmbedderPath() {
            do {
                let ctx = try LlamaEmbeddingContext.load(modelPath: path)
                self.context = ctx
                self.dimension = ctx.dimension
                self.modelFingerprint = ctx.modelFingerprint
                print("[EmbeddingModel] Loaded embedder '\(name)' dim=\(ctx.dimension) fp=\(ctx.modelFingerprint.prefix(12))…")
            } catch {
                print("[EmbeddingModel] ERROR: failed to load embedder at \(path): \(error)")
                self.context = nil
                self.dimension = 0
                self.modelFingerprint = ""
            }
        } else {
            print("[EmbeddingModel] ERROR: embedder GGUF '\(EmbeddingModel.embedderResourceName).\(EmbeddingModel.embedderResourceExt)' not found in bundle")
            self.context = nil
            self.dimension = 0
            self.modelFingerprint = ""
        }
    }

    /// Strict factory: throws if the embedder could not be loaded. Useful for
    /// PR-B and tests that must not run against a missing embedder.
    static func defaultInstance() throws -> EmbeddingModel {
        let model = EmbeddingModel(name: "default")
        guard model.context != nil else {
            throw EmbeddingError.modelLoadFailed(path: EmbeddingModel.resolveEmbedderPath() ?? "<not found>",
                                                 underlying: "embedder GGUF unavailable")
        }
        return model
    }

    /// テキストを埋め込みベクトルに変換（キャッシュ付き）
    func embed(text: String) -> [Float] {
        let prefixed = EmbeddingModel.taskPrefix + text

        // Check cache first (keyed on the prefixed string).
        if let cached = cacheQueue.sync(execute: { embeddingCache[prefixed] }) {
            return cached
        }

        guard let context = context else {
            print("[EmbeddingModel] ERROR: no embedding context loaded; returning empty vector")
            return []
        }

        let result = blockingEmbed(context: context, text: prefixed)

        // Only cache real results — never cache an empty (error) vector.
        if !result.isEmpty {
            cacheQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else { return }
                if self.embeddingCache.count >= self.maxCacheSize {
                    let oldest = self.embeddingCache.keys.prefix(50)
                    oldest.forEach { self.embeddingCache.removeValue(forKey: $0) }
                }
                self.embeddingCache[prefixed] = result
            }
        }

        return result
    }

    /// Blocking bridge from the synchronous public API to the async actor.
    /// Callers are expected to run off the main actor (retrieval already does).
    /// ADR-0000 §4: the actor throws on failure; the sync boundary can't rethrow,
    /// so we log loudly and return [] — visibly broken, not silently wrong.
    private func blockingEmbed(context: LlamaEmbeddingContext, text: String) -> [Float] {
        let sem = DispatchSemaphore(value: 0)
        var out: [Float] = []
        var failure: Error?
        Task.detached(priority: .userInitiated) {
            do { out = try await context.embed(text: text) }
            catch { failure = error }
            sem.signal()
        }
        sem.wait()
        if let failure = failure {
            print("[EmbeddingModel] ERROR: embed failed: \(failure)")
            return []
        }
        return out
    }

    /// Resolve the embedder GGUF in the app bundle (mirrors LlamaState.defaultModelUrl).
    static func resolveEmbedderPath() -> String? {
        let subs: [String?] = [nil, "Models", "Resources/Models", "Resources"]
        for sub in subs {
            if let url = Bundle.main.url(forResource: embedderResourceName,
                                         withExtension: embedderResourceExt,
                                         subdirectory: sub) {
                return url.path
            }
        }
        return nil
    }
}
