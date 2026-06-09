// Project: NoesisNoema
// File: LlamaEmbeddingContext.swift
// Description: llama.cpp embedding-mode actor (ADR-0011, PR-A foundation).
//   Parallel to `LlamaContext` (LibLlama.swift) but specialised for embedding
//   inference: pooling enabled, no sampler chain, single pooled vector out.
// License: MIT License
//
// EDIT POLICY (mirrors LibLlama.swift):
// - Only update to adapt to upstream llama.cpp C API changes or add thin shims.
// - Reuses the free helpers `llama_batch_clear` / `llama_batch_add` defined in
//   LibLlama.swift (do not redefine them here).

import Foundation
import CryptoKit
import llama

/// Errors surfaced by the embedding path. ADR-0000 §4: no silent fallback —
/// every failure throws a specific case; callers decide how to surface.
enum EmbeddingError: Error {
    case modelLoadFailed(path: String, underlying: String)
    case contextInitFailed
    case tokenizationFailed
    case decodeFailed(rc: Int32)
    case poolingUnavailable
    case zeroNorm
}

/// A llama.cpp context loaded in embedding mode (mean-pooled, L2-normalized output).
///
/// The embedder GGUF is replaceable: nothing here hard-codes nomic-embed beyond
/// the resource lookup in `EmbeddingModel`. Dimension is read from the model.
actor LlamaEmbeddingContext {

    // Isolated C handles — never touched off the actor.
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private var batch: llama_batch

    /// Embedding dimension as reported by the loaded model (`llama_model_n_embd`).
    nonisolated let dimension: Int

    /// SHA-256 hex digest of the GGUF file bytes, computed once at load.
    /// PR-B uses this for manifest fingerprint validation.
    nonisolated let modelFingerprint: String

    private init(model: OpaquePointer,
                 context: OpaquePointer,
                 vocab: OpaquePointer,
                 dimension: Int,
                 fingerprint: String) {
        self.model = model
        self.context = context
        self.vocab = vocab
        self.dimension = dimension
        self.modelFingerprint = fingerprint
        // n_batch == n_ctx == 8192 so a full-length chunk fits in one decode.
        self.batch = llama_batch_init(8192, 0, 1)
    }

    deinit {
        llama_batch_free(batch)
        llama_free(context)
        llama_model_free(model)
        // NOTE: intentionally NOT calling llama_backend_free() here — the backend
        // is shared process-wide with LlamaContext (LibLlama.swift). Freeing it
        // would tear down a live backend used by the generation path.
    }

    // MARK: - Load

    static func load(modelPath: String) throws -> LlamaEmbeddingContext {
        // Compute the fingerprint first (cheap, memory-mapped) so a failure here
        // doesn't leak a loaded model/context.
        let fingerprint = try computeFingerprint(path: modelPath)

        #if os(iOS)
        setenv("LLAMA_NO_METAL", "1", 1)
        #endif
        llama_backend_init()

        var model_params = llama_model_default_params()
        #if targetEnvironment(simulator)
        model_params.n_gpu_layers = 0
        #elseif os(iOS)
        model_params.n_gpu_layers = 0
        #else
        model_params.n_gpu_layers = 999 // macOS: use Metal when available
        #endif

        guard let model = llama_model_load_from_file(modelPath, model_params) else {
            throw EmbeddingError.modelLoadFailed(path: modelPath,
                                                 underlying: "llama_model_load_from_file returned nil")
        }

        let n_embd = Int(llama_model_n_embd(model))

        #if os(iOS)
        let nThreads: Int32 = 4
        #else
        let nThreads = Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))
        #endif

        var ctx_params = llama_context_default_params()
        ctx_params.embeddings       = true                       // critical: embedding mode
        ctx_params.n_ctx            = 8192                        // nomic-embed-text-v1.5 supports 8192
        ctx_params.n_batch          = 8192                        // a long chunk fits in a single batch
        ctx_params.n_ubatch         = 8192
        ctx_params.pooling_type     = LLAMA_POOLING_TYPE_MEAN     // mean pooling → one vector per sequence
        ctx_params.n_threads        = nThreads
        ctx_params.n_threads_batch  = nThreads

        guard let context = llama_init_from_model(model, ctx_params) else {
            llama_model_free(model)
            throw EmbeddingError.contextInitFailed
        }

        guard let vocab = llama_model_get_vocab(model) else {
            llama_free(context)
            llama_model_free(model)
            throw EmbeddingError.contextInitFailed
        }

        return LlamaEmbeddingContext(model: model,
                                     context: context,
                                     vocab: vocab,
                                     dimension: n_embd,
                                     fingerprint: fingerprint)
    }

    private static func computeFingerprint(path: String) throws -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else {
            throw EmbeddingError.modelLoadFailed(path: path,
                                                 underlying: "could not read GGUF bytes for fingerprint")
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Embed

    /// Returns the L2-normalized mean-pooled embedding for `text` as `dimension` float32s.
    func embed(text: String) async throws -> [Float] {
        var tokens = tokenize(text: text)
        guard !tokens.isEmpty else { throw EmbeddingError.tokenizationFailed }

        let nCtx = Int(llama_n_ctx(context))
        if tokens.count > nCtx {
            print("[LlamaEmbeddingContext] WARNING: input \(tokens.count) tokens > n_ctx \(nCtx); truncating")
            tokens = Array(tokens.prefix(nCtx))
        }

        // Build a single-sequence batch with logits disabled at every position —
        // we want pooled embeddings, not per-token logits.
        llama_batch_clear(&batch)
        for (i, tok) in tokens.enumerated() {
            llama_batch_add(&batch, tok, Int32(i), [0], false)
        }

        // Ensure embedding mode (also set at context init; belt-and-suspenders).
        llama_set_embeddings(context, true)

        let rc = llama_decode(context, batch)
        // ADR-0000 §4: do NOT print-and-continue. Throw on non-zero (mirrors the
        // parked L3 issue from PR #95 explicitly for the embedding path).
        if rc != 0 { throw EmbeddingError.decodeFailed(rc: rc) }

        // Sequence-0 pooled output (valid because pooling_type == MEAN).
        guard let ptr = llama_get_embeddings_seq(context, 0) else {
            throw EmbeddingError.poolingUnavailable
        }

        var vec = [Float](repeating: 0, count: dimension)
        for i in 0..<dimension { vec[i] = ptr[i] }

        // L2-normalize.
        var sumSq: Float = 0
        for v in vec { sumSq += v * v }
        let norm = sumSq.squareRoot()
        guard norm > 0, norm.isFinite else { throw EmbeddingError.zeroNorm }
        for i in 0..<dimension { vec[i] /= norm }

        return vec
    }

    // MARK: - Tokenization (mirrors LibLlama.tokenize, add_bos = true)

    private func tokenize(text: String) -> [llama_token] {
        let utf8Count = text.utf8.count
        let nMax = utf8Count + 2 // +BOS, +slack
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: nMax)
        defer { tokens.deallocate() }

        let n = llama_tokenize(vocab, text, Int32(utf8Count), tokens, Int32(nMax), true, false)
        guard n >= 0 else { return [] }

        var out: [llama_token] = []
        out.reserveCapacity(Int(n))
        for i in 0..<Int(n) { out.append(tokens[i]) }
        return out
    }
}
