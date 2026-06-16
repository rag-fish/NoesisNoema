// Project: NoesisNoema
// File: RAGpackManifest.swift
// Description: RAGpack v1.2 manifest model + validator (ADR-0011 §3-§7).
//   Mirrors the v1.2 manifest schema this app commits to (derived from
//   noesisnoema-pipeline's manifest_v1_1.json, lifted to the llama.cpp embedder
//   identity). Embedder identity is by fingerprint (model_hash), not name (§3).
// License: MIT License

import Foundation

/// Decoded `manifest.json` from a RAGpack v1.2 archive. Snake_case JSON keys map
/// to camelCase Swift via `CodingKeys`.
struct RAGpackManifest: Codable {
    let packVersion: String      // must equal "1.2"
    let packId: String
    let createdAt: String
    let chunker: ChunkerInfo
    let embedder: EmbedderInfo
    let indexer: IndexerInfo?      // informational — tolerate absence (ADR-0011 strict-only-on-identity)
    let files: FilesInfo
    let stats: StatsInfo?

    enum CodingKeys: String, CodingKey {
        case packVersion = "pack_version"
        case packId = "pack_id"
        case createdAt = "created_at"
        case chunker
        case embedder
        case indexer
        case files
        case stats
    }

    /// Informational chunker metadata. ALL fields optional: a chunker block must
    /// never be the reason a pack is rejected (ADR-0011 — strict only on identity).
    struct ChunkerInfo: Codable {
        let method: String?
        let chunkSize: Int?
        let overlap: Int?
        let tokenizerName: String?
        let preserveSentences: Bool?
        let configHash: String?

        enum CodingKeys: String, CodingKey {
            case method
            case chunkSize = "chunk_size"
            case overlap
            case tokenizerName = "tokenizer_name"
            case preserveSentences = "preserve_sentences"
            case configHash = "config_hash"
        }
    }

    struct EmbedderInfo: Codable {
        let embeddingModel: String      // human-readable name (NOT the identity)
        let embeddingDimension: Int
        let modelHash: String           // <-- the fingerprint (GGUF SHA-256), REQUIRED
        let dtype: String
        let pooling: String
        let l2Normalized: Bool
        let runtime: String?

        // Mean-centering gate (EmbeddingCorrection). Optional; absent/false means the
        // pack carries the legacy document-side embedding bias and the app should
        // recover it at import by removing the common direction. A pipeline that has
        // already mean-centered its document vectors sets this true so the app does
        // NOT double-correct a healthy pack. Informational — never fails validation.
        let meanCentered: Bool?

        enum CodingKeys: String, CodingKey {
            case embeddingModel = "embedding_model"
            case embeddingDimension = "embedding_dimension"
            case modelHash = "model_hash"
            case dtype
            case pooling
            case l2Normalized = "l2_normalized"
            case runtime
            case meanCentered = "mean_centered"
        }
    }

    /// Informational indexer metadata. ALL fields optional, covering BOTH known
    /// shapes: the original PR-B prompt's `{method, dimension}` (forward-compat) and
    /// the de-facto pipeline shape `{document_count, chunk_count, timestamp}`. An
    /// informational block must never fail decode (ADR-0011 — strict only on identity).
    struct IndexerInfo: Codable {
        let method: String?
        let dimension: Int?
        let documentCount: Int?
        let chunkCount: Int?
        let timestamp: String?

        enum CodingKeys: String, CodingKey {
            case method
            case dimension
            case documentCount = "document_count"
            case chunkCount = "chunk_count"
            case timestamp
        }
    }

    struct FilesInfo: Codable {
        let chunks: String
        let embeddings: String
        let citations: String?          // optional in v1.2
    }

    struct StatsInfo: Codable {
        let chunkCount: Int?
        let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case chunkCount = "chunk_count"
            case totalTokens = "total_tokens"
        }
    }
}

extension RAGpackManifest {
    /// Validates this manifest against the v1.2 spec AND against the app's
    /// currently-loaded embedder. Throws a specific `RAGpackImportError` on every
    /// violation — there is no silent fallback (ADR-0011 §4). The central §3 check
    /// is the fingerprint (`model_hash`) comparison.
    func validate(againstCurrentEmbedder current: EmbeddingModel) throws {
        guard packVersion == "1.2" else {
            throw RAGpackImportError.unsupportedPackVersion(found: packVersion)
        }
        guard embedder.dtype == "float32" else {
            throw RAGpackImportError.unsupportedEmbedderDtype(found: embedder.dtype)
        }
        guard embedder.pooling == "mean" else {
            throw RAGpackImportError.unsupportedEmbedderPooling(found: embedder.pooling)
        }
        guard embedder.l2Normalized else {
            throw RAGpackImportError.embedderNotL2Normalized
        }
        guard embedder.embeddingDimension == current.dimension else {
            throw RAGpackImportError.embedderDimensionMismatch(expected: current.dimension,
                                                               found: embedder.embeddingDimension)
        }
        // §3: identity is by fingerprint, not name. Case-insensitive hex compare.
        guard embedder.modelHash.lowercased() == current.modelFingerprint.lowercased() else {
            throw RAGpackImportError.embedderFingerprintMismatch(expected: current.modelFingerprint,
                                                                 found: embedder.modelHash)
        }
    }
}

#if DEBUG
extension RAGpackManifest {
    /// The REAL manifest.json from the first failing v1.2 pack (Spinoza Ethica,
    /// 406 chunks) — its `indexer` block uses the de-facto pipeline shape
    /// (`document_count`/`chunk_count`/`timestamp`), NOT the original PR-B
    /// `{method, dimension}` shape. Kept verbatim as a regression fixture.
    static let spinozaFixtureJSON = """
    {
      "pack_version": "1.2",
      "pack_id": "pack-9edb42ffa01d5da2c388d03f42562c70",
      "created_at": "2026-06-11T06:18:52Z",
      "chunker": { "method": "token_based", "chunk_size": 512, "overlap": 50, "tokenizer_name": "gpt2", "preserve_sentences": false, "config_hash": "a02e1eef8320ac74aae10efdfaaa0d703e2af4fccea685f355ea85f7918542ba" },
      "embedder": { "embedding_model": "nomic-embed-text-v1.5.Q5_K_M.gguf", "embedding_version": "0.3.28", "embedding_dimension": 768, "model_hash": "0c7930f6c4f6f29b7da5046e3a2c0832aa3f602db3de5760a95f0582dbd3d6e6", "dtype": "float32", "pooling": "mean", "l2_normalized": true, "name": "nomic-embed-text-v1.5.Q5_K_M.gguf", "version": "0.3.28", "dimensions": 768, "runtime": "llama.cpp" },
      "indexer": { "document_count": 1, "chunk_count": 406, "timestamp": "2026-06-11T06:18:52Z" },
      "files": { "chunks": "chunks.json", "embeddings": "embeddings.npy", "citations": "citations.jsonl", "metadata": { "embeddings_csv": "embeddings.csv", "manifest": "manifest.json" } },
      "source_documents": [ { "doc_id": "2015.263056.Ethics_text.txt", "title": "2015.263056.Ethics_text", "path": "/content/input/2015.263056.Ethics_text.txt", "source_hash": "c66d146a7faaa5bdf203aa5a6a2f38494bd4ca58063071cfc5e38847b34a9ed2", "char_count": 566764 } ]
    }
    """

    /// Manual decode smoke for the Spinoza fixture: asserts the manifest decodes
    /// (no throw) and that the strictly-required identity fields survived. Callable
    /// from a debugger or a scratch call site while the XCTest target is unwired.
    /// Returns the decoded manifest so a caller holding the live embedder can also
    /// run `validate(againstCurrentEmbedder:)` to exercise the §3 fingerprint check.
    @discardableResult
    static func runDecodeSmoke() -> RAGpackManifest {
        let m = try! JSONDecoder().decode(RAGpackManifest.self,
                                          from: Data(spinozaFixtureJSON.utf8))
        assert(m.packVersion == "1.2", "pack_version must decode strictly")
        assert(m.embedder.modelHash == "0c7930f6c4f6f29b7da5046e3a2c0832aa3f602db3de5760a95f0582dbd3d6e6")
        assert(m.embedder.embeddingDimension == 768 && m.embedder.dtype == "float32")
        assert(m.files.chunks == "chunks.json" && m.files.embeddings == "embeddings.npy")
        // Informational pipeline-shape indexer block decodes tolerantly.
        assert(m.indexer?.chunkCount == 406 && m.indexer?.documentCount == 1)
        assert(m.indexer?.method == nil && m.indexer?.dimension == nil)
        print("[RAGpackManifest] decode smoke PASSED — Spinoza v1.2 manifest decoded; "
              + "indexer.chunk_count=\(m.indexer?.chunkCount ?? -1)")
        return m
    }
}
#endif
