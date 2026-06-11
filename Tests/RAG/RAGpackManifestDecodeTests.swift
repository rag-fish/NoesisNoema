// Project: NoesisNoema
// File: RAGpackManifestDecodeTests.swift
// Description: Regression test for the v1.2 manifest contract fix — the app's
//   IndexerInfo originally required `{method, dimension}` (PR-B prompt shape), but
//   real pipeline packs ship `{document_count, chunk_count, timestamp}`. The first
//   real v1.2 import (Spinoza Ethica, 406 chunks) failed at decode with:
//     DecodingError.keyNotFound: Key 'method' not found ... Path: indexer.
//   ADR-0011 policy: strict only on identity/correctness (pack_version + embedder
//   block + files.chunks/embeddings); informational blocks decode tolerantly.
//
//   NOTE: the NoesisNoemaTests Xcode target is currently unwired (see PR-A note), so
//   this XCTest is committed for when the target is wired but is NOT exercised by
//   `xcodebuild test` today. A runnable `#if DEBUG` smoke
//   (`RAGpackManifest.runDecodeSmoke()`) lives in RAGpackManifest.swift for now.
// License: MIT License

import XCTest
@testable import NoesisNoema

final class RAGpackManifestDecodeTests: XCTestCase {

    /// The REAL manifest.json from the failing Spinoza pack — verbatim.
    private let spinozaManifestJSON = """
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

    private func decode(_ json: String) throws -> RAGpackManifest {
        try JSONDecoder().decode(RAGpackManifest.self, from: Data(json.utf8))
    }

    /// The pipeline-shape `indexer` block must decode without throwing, and the
    /// strictly-required identity fields must survive intact.
    func testDecodesRealSpinozaManifest() throws {
        let m = try decode(spinozaManifestJSON)

        // Strict identity fields — unchanged by this fix.
        XCTAssertEqual(m.packVersion, "1.2")
        XCTAssertEqual(m.embedder.modelHash,
                       "0c7930f6c4f6f29b7da5046e3a2c0832aa3f602db3de5760a95f0582dbd3d6e6")
        XCTAssertEqual(m.embedder.embeddingDimension, 768)
        XCTAssertEqual(m.embedder.dtype, "float32")
        XCTAssertEqual(m.embedder.pooling, "mean")
        XCTAssertTrue(m.embedder.l2Normalized)
        XCTAssertEqual(m.files.chunks, "chunks.json")
        XCTAssertEqual(m.files.embeddings, "embeddings.npy")

        // Informational pipeline-shape indexer block decodes tolerantly.
        XCTAssertEqual(m.indexer?.documentCount, 1)
        XCTAssertEqual(m.indexer?.chunkCount, 406)
        XCTAssertEqual(m.indexer?.timestamp, "2026-06-11T06:18:52Z")
        XCTAssertNil(m.indexer?.method)      // PR-B-shape fields simply absent
        XCTAssertNil(m.indexer?.dimension)

        // Informational chunker block also tolerated.
        XCTAssertEqual(m.chunker.method, "token_based")
        XCTAssertEqual(m.chunker.chunkSize, 512)
    }

    /// The original PR-B `{method, dimension}` indexer shape must STILL decode
    /// (forward-compat) — both shapes are accepted.
    func testDecodesOriginalPRBIndexerShape() throws {
        let json = spinozaManifestJSON.replacingOccurrences(
            of: "\"indexer\": { \"document_count\": 1, \"chunk_count\": 406, \"timestamp\": \"2026-06-11T06:18:52Z\" },",
            with: "\"indexer\": { \"method\": \"flat\", \"dimension\": 768 },")
        let m = try decode(json)
        XCTAssertEqual(m.indexer?.method, "flat")
        XCTAssertEqual(m.indexer?.dimension, 768)
        XCTAssertNil(m.indexer?.chunkCount)
    }

    /// An omitted `indexer` block (future producer) must not fail decode.
    func testDecodesWithIndexerOmitted() throws {
        let json = spinozaManifestJSON.replacingOccurrences(
            of: "\"indexer\": { \"document_count\": 1, \"chunk_count\": 406, \"timestamp\": \"2026-06-11T06:18:52Z\" },",
            with: "")
        let m = try decode(json)
        XCTAssertNil(m.indexer)
    }

    /// Full validate path incl. the §3 fingerprint check — requires the live
    /// embedder (git-ignored GGUF must be bundled). Skipped when unavailable so
    /// the suite stays green on CI without the model.
    func testValidatesAgainstCurrentEmbedderWhenAvailable() throws {
        guard let embedder = try? EmbeddingModel.defaultInstance() else {
            throw XCTSkip("Embedder GGUF unavailable; skipping fingerprint validation.")
        }
        let m = try decode(spinozaManifestJSON)
        // Asserts the fixture's model_hash matches the current embedder fingerprint.
        XCTAssertNoThrow(try m.validate(againstCurrentEmbedder: embedder),
                         "Spinoza pack fingerprint must match the current embedder.")
    }
}
