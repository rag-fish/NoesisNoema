// Project: NoesisNoema
// File: RAGpackChunksDecodeTests.swift
// Description: Regression test for the v1.2 chunks.json shape fix (ADR-0011 §5).
//   The first real v1.2 import (Spinoza Ethica, 406 chunks) failed at the chunks
//   decode step with:
//     RAGpack Import Failed
//     The RAGpack chunks.json could not be read: DecodingError.typeMismatch:
//     expected value of type Dictionary<String, Any>. Path: [0]. … Expected to
//     decode Dictionary<String, Any> but found a string instead.
//   Root cause: the pipeline writes chunks.json as a FLAT ARRAY OF CHUNK TEXT
//   (`chunks_json = [chunk['text'] for chunk in chunks_with_metadata]` in
//   writer/pack_writer.py), NOT an array of objects. All per-chunk metadata lives
//   in citations.jsonl keyed by `chunk_index`, aligned to the embeddings.npy row.
//   The reader now decodes `[String]` and assembles `[Chunk]` in memory by joining
//   text[i] + embeddings[i] + citations[i].
//
//   These tests exercise `RAGpackReader.buildChunks` directly — the pure assembly
//   seam — so they need no FileManager and no live embedder GGUF.
//
//   NOTE: the NoesisNoemaTests Xcode target is currently unwired (see PR-A/#99
//   notes), so this XCTest is committed for when the target is wired but is NOT
//   exercised by `xcodebuild test` today. A runnable `#if DEBUG` smoke
//   (`RAGpackReader.runChunksSmoke()`) lives in RAGpackReader.swift for now.
// License: MIT License

import XCTest
@testable import NoesisNoema

final class RAGpackChunksDecodeTests: XCTestCase {

    /// 3 rows of 768-dim zero embeddings — the same shape NumpyReader would yield
    /// for a mock 3×768 embeddings.npy. The values are irrelevant to assembly.
    private let embeddings: [[Float]] = (0..<3).map { _ in Array(repeating: Float(0), count: 768) }

    private let chunksJSON = Data(#"["alpha","beta","gamma"]"#.utf8)

    private let citationsJSONL = Data("""
    {"chunk_index": 0, "doc_id": "test", "page": 1, "char_start": 0, "char_end": 5, "snippet": "alpha"}
    {"chunk_index": 1, "doc_id": "test", "page": 1, "char_start": 5, "char_end": 9, "snippet": "beta"}
    {"chunk_index": 2, "doc_id": "test", "page": 2, "char_start": 9, "char_end": 14, "snippet": "gamma"}
    """.utf8)

    // MARK: - POSITIVE: [String] chunks.json joins with embeddings + citations.

    func testBuildsChunksFromStringArrayAndCitations() throws {
        let chunks = try RAGpackReader.buildChunks(chunksJSON: chunksJSON,
                                                   embeddings: embeddings,
                                                   citationsJSONL: citationsJSONL)

        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks.map(\.content), ["alpha", "beta", "gamma"])

        // Citation fields wired by index; the extra `snippet` key is ignored.
        XCTAssertEqual(chunks.map(\.docId), ["test", "test", "test"])
        XCTAssertEqual(chunks[0].page, 1)
        XCTAssertEqual(chunks[0].charStart, 0)
        XCTAssertEqual(chunks[0].charEnd, 5)
        XCTAssertEqual(chunks[2].page, 2)
        XCTAssertEqual(chunks[2].charEnd, 14)

        // Each chunk carries its embedding row (the count cross-check passed).
        XCTAssertTrue(chunks.allSatisfy { $0.embedding.count == 768 })
    }

    /// citations.jsonl is optional in v1.2 — a nil file must still build chunks.
    func testBuildsChunksWithoutCitations() throws {
        let chunks = try RAGpackReader.buildChunks(chunksJSON: chunksJSON,
                                                   embeddings: embeddings,
                                                   citationsJSONL: nil)
        XCTAssertEqual(chunks.map(\.content), ["alpha", "beta", "gamma"])
        XCTAssertTrue(chunks.allSatisfy { $0.docId == nil && $0.page == nil })
    }

    // MARK: - NEGATIVE: the OLD object shape must be rejected.

    /// Locks the §5 contract: chunks.json carrying objects (`[{"text": "alpha"}, …]`)
    /// — the pre-fix shape the reader used to decode — MUST throw `.chunksMalformed`.
    func testRejectsObjectShapeChunks() {
        let objectShape = Data(#"[{"text":"alpha"},{"text":"beta"},{"text":"gamma"}]"#.utf8)
        XCTAssertThrowsError(
            try RAGpackReader.buildChunks(chunksJSON: objectShape,
                                          embeddings: embeddings,
                                          citationsJSONL: nil)
        ) { error in
            guard case RAGpackImportError.chunksMalformed = error else {
                return XCTFail("expected .chunksMalformed, got \(error)")
            }
        }
    }

    // MARK: - Cross-checks preserved.

    /// chunk count != embedding count → `.chunksEmbeddingsCountMismatch`.
    func testCountMismatchThrows() {
        let twoRows: [[Float]] = Array(embeddings.prefix(2))
        XCTAssertThrowsError(
            try RAGpackReader.buildChunks(chunksJSON: chunksJSON,
                                          embeddings: twoRows,
                                          citationsJSONL: nil)
        ) { error in
            guard case RAGpackImportError.chunksEmbeddingsCountMismatch(let c, let e) = error else {
                return XCTFail("expected .chunksEmbeddingsCountMismatch, got \(error)")
            }
            XCTAssertEqual(c, 3)
            XCTAssertEqual(e, 2)
        }
    }

    /// A non-empty citations file whose record count != chunk count → `.citationsMalformed`.
    func testCitationCountMismatchThrows() {
        let twoCitations = Data("""
        {"chunk_index": 0, "doc_id": "test"}
        {"chunk_index": 1, "doc_id": "test"}
        """.utf8)
        XCTAssertThrowsError(
            try RAGpackReader.buildChunks(chunksJSON: chunksJSON,
                                          embeddings: embeddings,
                                          citationsJSONL: twoCitations)
        ) { error in
            guard case RAGpackImportError.citationsMalformed = error else {
                return XCTFail("expected .citationsMalformed, got \(error)")
            }
        }
    }

    /// A citation referencing a chunk_index outside [0, chunks.count) → `.citationsMalformed`.
    func testCitationIndexOutOfRangeThrows() {
        let outOfRange = Data("""
        {"chunk_index": 0, "doc_id": "test"}
        {"chunk_index": 1, "doc_id": "test"}
        {"chunk_index": 9, "doc_id": "test"}
        """.utf8)
        XCTAssertThrowsError(
            try RAGpackReader.buildChunks(chunksJSON: chunksJSON,
                                          embeddings: embeddings,
                                          citationsJSONL: outOfRange)
        ) { error in
            guard case RAGpackImportError.citationsMalformed = error else {
                return XCTFail("expected .citationsMalformed, got \(error)")
            }
        }
    }
}
