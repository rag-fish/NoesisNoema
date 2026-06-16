// Project: NoesisNoema
// File: RAGpackReader.swift
// Description: RAGpack v1.2 reader (ADR-0011 §3-§7). Reads an unzipped pack
//   (manifest.json + chunks.json + embeddings.npy + optional citations.jsonl),
//   validates the manifest against the current embedder, and returns parsed
//   chunks with embeddings. Throws a structured error on every malformation —
//   no silent fallback (§4), no v0.x CSV path (anti-goal).
//
//   v1.2 two-file split (ADR-0011 §5): the pipeline writes chunks.json as a FLAT
//   ARRAY OF CHUNK TEXT (`["First chunk…", "Second chunk…", …]`) — NOT an array of
//   objects. All per-chunk metadata lives in citations.jsonl, one record per line
//   keyed by `chunk_index`, aligned with the embeddings.npy row order. We decode
//   chunks.json as `[String]`, then assemble `[Chunk]` in memory by joining each
//   text with `embeddings[i]` and `citations[i]`. The app is a CONSUMER of v1.2
//   packs; it never emits the object shape.
// License: MIT License

import Foundation

struct RAGpackReader {

    /// Reads a v1.2 RAGpack from an already-unzipped directory.
    /// - Parameters:
    ///   - unzippedDir: directory containing manifest.json, chunks.json,
    ///     embeddings.npy, and optionally citations.jsonl.
    ///   - embedder: the app's current `EmbeddingModel` — used to validate the
    ///     embedder fingerprint and dimension (ADR-0011 §3).
    /// - Returns: `chunks` (each carrying its embedding and any citation metadata),
    ///   the parallel `embeddings` matrix, and `correctionMean` — the L2-normalized
    ///   common direction removed from the document vectors (nil when no correction
    ///   was applied, i.e. the pack is already `mean_centered`). The caller stores
    ///   `correctionMean` per pack so the query can be corrected with the SAME
    ///   direction at search time (EmbeddingCorrection / mean-centering recovery).
    static func readPack(at unzippedDir: URL,
                         embedder: EmbeddingModel) throws -> (chunks: [Chunk],
                                                              embeddings: [[Float]],
                                                              correctionMean: [Float]?) {
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

        // 3. embeddings.npy → (shape, flat). Read BEFORE chunks because v1.2 chunk
        //    assembly joins each chunk text with its embedding row by index.
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

        // 4. Reshape flat → [[Float]] of length shape[0], each row shape[1].
        let rowCount = shape[0]
        let dim = shape[1]
        var embeddings: [[Float]] = []
        embeddings.reserveCapacity(rowCount)
        for r in 0..<rowCount {
            let start = r * dim
            embeddings.append(Array(flat[start..<(start + dim)]))
        }

        // 4b. Mean-centering recovery (EmbeddingCorrection). Legacy packs ship
        //     document vectors collapsed onto a shared direction (a pipeline-side
        //     embedding bias) that destroys retrieval discrimination. Unless the pack
        //     declares itself already `mean_centered`, remove that common direction
        //     from every document vector here and return the direction so the query
        //     can be corrected identically at search time. No-op for healthy packs.
        let alreadyCentered = manifest.embedder.meanCentered ?? false
        let preNorm = EmbeddingCorrection.meanVectorNorm(of: embeddings)
        let correctionMean: [Float]?
        if alreadyCentered {
            correctionMean = nil
            SystemLog().logEvent(event: String(
                format: "[RAGpackReader] mean-centering SKIPPED (manifest mean_centered=true); rows=%d dim=%d preMeanNorm=%.3f",
                rowCount, dim, preNorm))
        } else {
            let (corrected, meanDir) = EmbeddingCorrection.apply(to: embeddings, alreadyMeanCentered: false)
            embeddings = corrected
            correctionMean = meanDir
            let postNorm = EmbeddingCorrection.meanVectorNorm(of: embeddings)
            SystemLog().logEvent(event: String(
                format: "[RAGpackReader] mean-centering APPLIED=%@ rows=%d dim=%d preMeanNorm=%.3f postMeanNorm=%.3f",
                meanDir == nil ? "false(no-direction)" : "true", rowCount, dim, preNorm, postNorm))
        }

        // 5. chunks.json → [String] (flat array of chunk TEXT, NOT objects), then
        //    join with embeddings + optional citations.jsonl to build [Chunk].
        let chunksURL = unzippedDir.appendingPathComponent(manifest.files.chunks)
        guard fm.fileExists(atPath: chunksURL.path) else {
            throw RAGpackImportError.chunksMissing
        }
        let chunksData: Data
        do {
            chunksData = try Data(contentsOf: chunksURL)
        } catch {
            throw RAGpackImportError.chunksMalformed(underlying: String(describing: error))
        }

        // citations.jsonl — optional in v1.2. Read its bytes here; buildChunks parses,
        // count-checks, and joins them (it used to be a post-attach step).
        var citationsData: Data? = nil
        if let citationsName = manifest.files.citations {
            let citationsURL = unzippedDir.appendingPathComponent(citationsName)
            if fm.fileExists(atPath: citationsURL.path) {
                do {
                    citationsData = try Data(contentsOf: citationsURL)
                } catch {
                    throw RAGpackImportError.citationsMalformed(underlying: String(describing: error))
                }
            }
        }

        let chunks = try buildChunks(chunksJSON: chunksData,
                                     embeddings: embeddings,
                                     citationsJSONL: citationsData)

        // 6. Done. `embeddings` (and the chunk embeddings built from them) are
        //    already mean-centered when `correctionMean != nil`.
        return (chunks, embeddings, correctionMean)
    }

    /// Assembles the in-memory `[Chunk]` from the v1.2 two-file split (ADR-0011 §5).
    /// Pure over its inputs (no FileManager / no embedder) so it is the unit-test
    /// seam for the reader: it owns the `[String]` decode, the chunk↔embedding count
    /// cross-check, and the citations join.
    ///
    /// - Parameters:
    ///   - chunksJSON: raw bytes of chunks.json — a flat JSON array of chunk text.
    ///   - embeddings: the reshaped embeddings matrix; `embeddings[i]` is row i.
    ///   - citationsJSONL: raw bytes of citations.jsonl, or nil if the file is absent
    ///     (citations are optional in v1.2). Empty content is treated as absent.
    /// - Returns: `[Chunk]` with `content`/`embedding`/citation fields wired by index.
    static func buildChunks(chunksJSON: Data,
                            embeddings: [[Float]],
                            citationsJSONL: Data?) throws -> [Chunk] {
        // 1. chunks.json MUST be [String]. An object shape (the pre-v1.2 [Chunk]
        //    shape) is now a hard error — this locks the §5 contract.
        let texts: [String]
        do {
            texts = try JSONDecoder().decode([String].self, from: chunksJSON)
        } catch {
            throw RAGpackImportError.chunksMalformed(
                underlying: "expected [String], got: \(String(describing: error))")
        }

        // 2. Cross-check chunk / embedding counts (preserved exactly).
        guard texts.count == embeddings.count else {
            throw RAGpackImportError.chunksEmbeddingsCountMismatch(chunks: texts.count,
                                                                  embeddings: embeddings.count)
        }

        // 3. citations.jsonl → [chunk_index: CitationRecord]. Optional: a missing or
        //    empty file is fine. When present and non-empty, its record count must
        //    equal the chunk count, and every chunk_index must be in range.
        let citations = try parseCitations(citationsJSONL, chunkCount: texts.count)

        // 4. Build each Chunk by joining text[i] + embeddings[i] + citations[i].
        var chunks: [Chunk] = []
        chunks.reserveCapacity(texts.count)
        for i in texts.indices {
            let cite = citations[i]
            chunks.append(Chunk(content: texts[i],
                                embedding: embeddings[i],
                                page: cite?.page,
                                docId: cite?.docId,
                                charStart: cite?.charStart,
                                charEnd: cite?.charEnd,
                                paragraphBoundaries: cite?.paragraphBoundaries))
        }
        return chunks
    }

    /// Parses citations.jsonl (one JSON object per line) into a dict keyed by
    /// `chunk_index`. Errors → `.citationsMalformed`. Returns an empty dict for a
    /// nil/empty file. Enforces: record count == chunkCount (when non-empty) and
    /// every `chunk_index` ∈ `[0, chunkCount)`.
    private static func parseCitations(_ data: Data?, chunkCount: Int) throws -> [Int: CitationRecord] {
        guard let data = data, !data.isEmpty else { return [:] }
        guard let raw = String(data: data, encoding: .utf8) else {
            throw RAGpackImportError.citationsMalformed(underlying: "citations.jsonl is not valid UTF-8")
        }
        let lines = raw.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" })
        var byIndex: [Int: CitationRecord] = [:]
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
            guard idx >= 0 && idx < chunkCount else {
                throw RAGpackImportError.citationsMalformed(
                    underlying: "chunk_index \(idx) out of range (0..<\(chunkCount))")
            }
            byIndex[idx] = record
        }
        // If the file carried citations, it must cover every chunk 1:1.
        if !byIndex.isEmpty && byIndex.count != chunkCount {
            throw RAGpackImportError.citationsMalformed(
                underlying: "citation count \(byIndex.count) != chunks count \(chunkCount)")
        }
        return byIndex
    }

    /// One line of citations.jsonl. Derived from noesisnoema-pipeline's
    /// `chunk_text_with_offsets` output. Any extra keys (e.g. `snippet`) are ignored.
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

#if DEBUG
extension RAGpackReader {
    /// Manual smoke for the v1.2 two-file split (ADR-0011 §5), runnable from a
    /// debugger or scratch call site while the NoesisNoemaTests Xcode target is
    /// unwired. Exercises `buildChunks` directly (no FileManager / no embedder):
    ///   - POSITIVE: chunks.json = ["alpha","beta","gamma"] + 3×768 zero embeddings +
    ///     citations.jsonl (3 lines, chunk_index 0..2, doc_id "test") → 3 Chunks with
    ///     content matched and citation fields wired.
    ///   - NEGATIVE: the OLD object shape [{"text":"alpha"},…] MUST throw .chunksMalformed.
    static func runChunksSmoke() {
        let texts = ["alpha", "beta", "gamma"]
        let embeddings: [[Float]] = (0..<3).map { _ in Array(repeating: Float(0), count: 768) }
        let chunksJSON = Data("[\"alpha\",\"beta\",\"gamma\"]".utf8)
        let citationsJSONL = Data("""
        {"chunk_index": 0, "doc_id": "test", "page": 1, "char_start": 0, "char_end": 5, "snippet": "alpha"}
        {"chunk_index": 1, "doc_id": "test", "page": 1, "char_start": 5, "char_end": 9}
        {"chunk_index": 2, "doc_id": "test", "page": 2, "char_start": 9, "char_end": 14}
        """.utf8)

        // POSITIVE
        let chunks = try! buildChunks(chunksJSON: chunksJSON,
                                      embeddings: embeddings,
                                      citationsJSONL: citationsJSONL)
        assert(chunks.count == 3, "expected 3 chunks")
        assert(chunks.map(\.content) == texts, "content must match chunks.json strings")
        assert(chunks.allSatisfy { $0.docId == "test" }, "doc_id must be joined from citations")
        assert(chunks[0].charStart == 0 && chunks[0].charEnd == 5, "char offsets must be joined")
        assert(chunks.allSatisfy { $0.embedding.count == 768 }, "embedding row must be wired")

        // NEGATIVE — old object shape must be rejected.
        let objectShape = Data("[{\"text\":\"alpha\"},{\"text\":\"beta\"},{\"text\":\"gamma\"}]".utf8)
        var threw = false
        do {
            _ = try buildChunks(chunksJSON: objectShape, embeddings: embeddings, citationsJSONL: nil)
        } catch RAGpackImportError.chunksMalformed {
            threw = true
        } catch {
            assertionFailure("expected .chunksMalformed, got \(error)")
        }
        assert(threw, "object-shape chunks.json MUST throw .chunksMalformed")

        print("[RAGpackReader] chunks smoke PASSED — [String] decode + citations join + "
              + "object-shape rejection all hold (ADR-0011 §5).")
    }
}
#endif
