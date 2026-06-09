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
    let indexer: IndexerInfo
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

    struct ChunkerInfo: Codable {
        let method: String
        let chunkSize: Int
        let overlap: Int
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

        enum CodingKeys: String, CodingKey {
            case embeddingModel = "embedding_model"
            case embeddingDimension = "embedding_dimension"
            case modelHash = "model_hash"
            case dtype
            case pooling
            case l2Normalized = "l2_normalized"
            case runtime
        }
    }

    struct IndexerInfo: Codable {
        let method: String
        let dimension: Int
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
