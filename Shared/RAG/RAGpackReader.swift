// Project: NoesisNoema
// File: RAGpackReader.swift
// Description: RAGpack v1.2 reader (ADR-0011 §3-§7). Reads an unzipped pack
//   (manifest.json + chunks.json + embeddings.npy + optional citations.jsonl),
//   validates the manifest against the current embedder, and returns parsed
//   chunks with embeddings. Throws a structured error on every malformation —
//   no silent fallback (§4), no v0.x CSV path (anti-goal).
// License: MIT License

import Foundation

struct RAGpackReader {

    /// Reads a v1.2 RAGpack from an already-unzipped directory.
    /// - Parameters:
    ///   - unzippedDir: directory containing manifest.json, chunks.json,
    ///     embeddings.npy, and optionally citations.jsonl.
    ///   - embedder: the app's current `EmbeddingModel` — used to validate the
    ///     embedder fingerprint and dimension (ADR-0011 §3).
    /// - Returns: `chunks` (each carrying its embedding and any citation metadata)
    ///   and the parallel `embeddings` matrix.
    static func readPack(at unzippedDir: URL,
                         embedder: EmbeddingModel) throws -> (chunks: [Chunk],
                                                              embeddings: [[Float]]) {
        let fm = FileManager.default

        // 1. manifest.json → RAGpackManifest
        let manifestURL = unzippedDir.appendingPathComponent("manifest.json")
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw RAGpackImportError.manifestMissing
        }
        let manifest: RAGpackManifest
        do {
            let data = try Data(contentsOf: manifestURL)
            manifest = try JSONDecoder().decode(RAGpackManifest.self, from: data)
        } catch let e as RAGpackImportError {
            throw e
        } catch {
            throw RAGpackImportError.manifestMalformed(underlying: String(describing: error))
        }

        // 2. Validate schema + embedder identity (throws on every violation).
        try manifest.validate(againstCurrentEmbedder: embedder)

        // 3. chunks.json → [Chunk] (embeddings filled from the .npy in step 5).
        let chunksURL = unzippedDir.appendingPathComponent(manifest.files.chunks)
        guard fm.fileExists(atPath: chunksURL.path) else {
            throw RAGpackImportError.chunksMissing
        }
        var chunks: [Chunk]
        do {
            let data = try Data(contentsOf: chunksURL)
            chunks = try JSONDecoder().decode([Chunk].self, from: data)
        } catch {
            throw RAGpackImportError.chunksMalformed(underlying: String(describing: error))
        }

        // 4. embeddings.npy → (shape, flat)
        let embeddingsURL = unzippedDir.appendingPathComponent(manifest.files.embeddings)
        guard fm.fileExists(atPath: embeddingsURL.path) else {
            throw RAGpackImportError.embeddingsMissing
        }
        let shape: [Int]
        let flat: [Float]
        do {
            (shape, flat) = try NumpyReader.readFloat32(from: embeddingsURL)
        } catch {
            throw RAGpackImportError.embeddingsMalformed(underlying: String(describing: error))
        }
        guard shape.count == 2, shape[1] == embedder.dimension else {
            throw RAGpackImportError.embeddingShapeUnexpected(shape: shape)
        }

        // 5. Reshape flat → [[Float]] of length shape[0], each row shape[1].
        let rowCount = shape[0]
        let dim = shape[1]
        var embeddings: [[Float]] = []
        embeddings.reserveCapacity(rowCount)
        for r in 0..<rowCount {
            let start = r * dim
            embeddings.append(Array(flat[start..<(start + dim)]))
        }

        // 6. Cross-check chunk / embedding counts.
        guard chunks.count == embeddings.count else {
            throw RAGpackImportError.chunksEmbeddingsCountMismatch(chunks: chunks.count,
                                                                  embeddings: embeddings.count)
        }

        // Attach each embedding row to its chunk so the returned chunks are fully
        // formed for the VectorStore (which keys/searches on Chunk.embedding).
        for i in chunks.indices {
            chunks[i].embedding = embeddings[i]
        }

        // 7. citations.jsonl — optional. If present, attach per-chunk metadata by index.
        if let citationsName = manifest.files.citations {
            let citationsURL = unzippedDir.appendingPathComponent(citationsName)
            if fm.fileExists(atPath: citationsURL.path) {
                try attachCitations(from: citationsURL, to: &chunks)
            }
        }

        // 8. Done.
        return (chunks, embeddings)
    }

    /// Parses citations.jsonl (one JSON object per line) and attaches the citation
    /// fields to the matching chunk by `chunk_index`. Errors → `.citationsMalformed`.
    private static func attachCitations(from url: URL, to chunks: inout [Chunk]) throws {
        let raw: String
        do {
            raw = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw RAGpackImportError.citationsMalformed(underlying: String(describing: error))
        }
        let lines = raw.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" })
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let lineData = trimmed.data(using: .utf8) else {
                throw RAGpackImportError.citationsMalformed(underlying: "line is not valid UTF-8")
            }
            let record: CitationRecord
            do {
                record = try JSONDecoder().decode(CitationRecord.self, from: lineData)
            } catch {
                throw RAGpackImportError.citationsMalformed(underlying: String(describing: error))
            }
            let idx = record.chunkIndex
            guard idx >= 0 && idx < chunks.count else {
                throw RAGpackImportError.citationsMalformed(
                    underlying: "chunk_index \(idx) out of range (0..<\(chunks.count))")
            }
            if let docId = record.docId { chunks[idx].docId = docId }
            if let page = record.page { chunks[idx].page = page }
            if let s = record.charStart { chunks[idx].charStart = s }
            if let e = record.charEnd { chunks[idx].charEnd = e }
            if let pb = record.paragraphBoundaries { chunks[idx].paragraphBoundaries = pb }
        }
    }

    /// One line of citations.jsonl. Derived from noesisnoema-pipeline's
    /// `chunk_text_with_offsets` output.
    private struct CitationRecord: Decodable {
        let chunkIndex: Int
        let docId: String?
        let page: Int?
        let charStart: Int?
        let charEnd: Int?
        let paragraphBoundaries: [Int]?

        enum CodingKeys: String, CodingKey {
            case chunkIndex = "chunk_index"
            case docId = "doc_id"
            case page
            case charStart = "char_start"
            case charEnd = "char_end"
            case paragraphBoundaries = "paragraph_boundaries"
        }
    }
}

enum RAGpackImportError: Error, LocalizedError, Identifiable {
    case manifestMissing
    case manifestMalformed(underlying: String)
    case chunksMissing
    case chunksMalformed(underlying: String)
    case embeddingsMissing
    case embeddingsMalformed(underlying: String)
    case citationsMalformed(underlying: String)
    case unsupportedPackVersion(found: String)
    case unsupportedEmbedderDtype(found: String)
    case unsupportedEmbedderPooling(found: String)
    case embedderNotL2Normalized
    case embedderDimensionMismatch(expected: Int, found: Int)
    case embedderFingerprintMismatch(expected: String, found: String)
    case chunksEmbeddingsCountMismatch(chunks: Int, embeddings: Int)
    case embeddingShapeUnexpected(shape: [Int])

    /// Stable identity so SwiftUI `.alert(item:)` can present the error.
    var id: String { errorDescription ?? "ragpack-import-error" }

    var errorDescription: String? {
        switch self {
        case .manifestMissing:
            return "This RAGpack is missing manifest.json. It is not a valid v1.2 pack."
        case .manifestMalformed(let underlying):
            return "The RAGpack manifest.json could not be read: \(underlying)"
        case .chunksMissing:
            return "This RAGpack is missing its chunks.json file."
        case .chunksMalformed(let underlying):
            return "The RAGpack chunks.json could not be read: \(underlying)"
        case .embeddingsMissing:
            return "This RAGpack is missing its embeddings.npy file."
        case .embeddingsMalformed(let underlying):
            return "The RAGpack embeddings.npy could not be read: \(underlying)"
        case .citationsMalformed(let underlying):
            return "The RAGpack citations.jsonl could not be read: \(underlying)"
        case .unsupportedPackVersion(let found):
            return "Unsupported RAGpack version “\(found)”. This app requires v1.2."
        case .unsupportedEmbedderDtype(let found):
            return "Unsupported embedding dtype “\(found)”. Only float32 is supported."
        case .unsupportedEmbedderPooling(let found):
            return "Unsupported embedding pooling “\(found)”. Only mean pooling is supported."
        case .embedderNotL2Normalized:
            return "This RAGpack's embeddings are not L2-normalized, which this app requires."
        case .embedderDimensionMismatch(let expected, let found):
            return "Embedding dimension mismatch: this pack has \(found)-dim vectors, but the app's embedder produces \(expected)-dim."
        case .embedderFingerprintMismatch(let expected, let found):
            return "This RAGpack was built with a different embedding model than the app uses, so retrieval would be wrong. Re-generate the pack with the current embedder.\n\nExpected fingerprint: \(expected.prefix(16))…\nPack fingerprint: \(found.prefix(16))…"
        case .chunksEmbeddingsCountMismatch(let chunks, let embeddings):
            return "Corrupt RAGpack: \(chunks) chunks but \(embeddings) embeddings."
        case .embeddingShapeUnexpected(let shape):
            return "Unexpected embeddings shape \(shape); expected a 2-D (N, dimension) array."
        }
    }
}
