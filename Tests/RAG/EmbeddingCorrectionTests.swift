// Project: NoesisNoema
// File: EmbeddingCorrectionTests.swift
// Description: Unit + regression tests for the mean-centering recovery layer
//   (EmbeddingCorrection / QueryCorrector). Document vectors in legacy RAGpacks
//   collapse onto a shared direction; removing it restores retrieval discrimination.
//
//   These tests are pure and deterministic (no GGUF / no model load): a synthetic
//   "collapsed" corpus reproduces the measured pathology exactly (high off-diagonal
//   cosine, low effective dimensionality, negligible top1-vs-top10 gap), and the
//   tests assert the helper recovers it. The transform under test is the design's:
//     mean_dir = normalize(mean(docs)); d' = normalize(d - mean_dir); same for q.
//
//   NOTE: like the sibling RAG tests, the NoesisNoemaTests Xcode target is currently
//   unwired, so these are committed for when it is wired and are NOT run by
//   `xcodebuild test` today.
// License: MIT License

import XCTest
@testable import NoesisNoema

final class EmbeddingCorrectionTests: XCTestCase {

    // MARK: - Synthetic collapsed corpus

    /// Builds `n` unit vectors of the form `normalize(alpha·sharedAxis + uniqueAxis_i)`.
    /// They all share a dominant common direction (axis 0) — exactly the collapse this
    /// feature recovers from. Each chunk's unique semantic axis is distinct.
    private func collapsedCorpus(n: Int, dim: Int, alpha: Float) -> [[Float]] {
        precondition(dim >= n + 1, "need one shared axis + one unique axis per chunk")
        var out: [[Float]] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            var v = [Float](repeating: 0, count: dim)
            v[0] = alpha        // shared (collapse) direction
            v[i + 1] = 1        // unique semantic direction
            out.append(EmbeddingCorrection.l2Normalized(v))
        }
        return out
    }

    /// Full cosine, mirroring the retriever's similarity (defensive — divides by norms).
    private func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<min(a.count, b.count) { dot += a[i]*b[i]; na += a[i]*a[i]; nb += b[i]*b[i] }
        let d = na.squareRoot() * nb.squareRoot()
        return d == 0 ? 0 : dot / d
    }

    // MARK: - 1. Injected common bias is removed

    func testRemovesInjectedCommonBias() {
        let raw = collapsedCorpus(n: 12, dim: 16, alpha: 3)
        let rawOff = EmbeddingCorrection.averageOffDiagonalCosine(of: raw)
        XCTAssertGreaterThan(rawOff, 0.6, "synthetic corpus must start collapsed (high off-diagonal cosine)")

        let (corrected, meanDir) = EmbeddingCorrection.removeCommonDirection(from: raw)
        XCTAssertNotNil(meanDir, "a usable common direction must be found")

        let corrOff = EmbeddingCorrection.averageOffDiagonalCosine(of: corrected)
        XCTAssertLessThan(abs(corrOff), 0.25, "after removing the common direction the corpus is ~orthogonal")
        XCTAssertLessThan(abs(corrOff), abs(rawOff) / 2, "off-diagonal cosine at least halved")

        // Correction must preserve unit length (renormalized residuals).
        for v in corrected {
            XCTAssertEqual(EmbeddingCorrection.l2Norm(v), 1.0, accuracy: 1e-4)
        }
        // And it must collapse the mean-vector norm (alignment) toward 0.
        XCTAssertGreaterThan(EmbeddingCorrection.meanVectorNorm(of: raw), 0.8)
        XCTAssertLessThan(EmbeddingCorrection.meanVectorNorm(of: corrected),
                          EmbeddingCorrection.meanVectorNorm(of: raw))
    }

    // MARK: - 2. mean_centered == true → strict no-op

    func testMeanCenteredManifestIsNoOp() {
        let raw = collapsedCorpus(n: 8, dim: 16, alpha: 3)

        let (identity, meanDir) = EmbeddingCorrection.apply(to: raw, alreadyMeanCentered: true)
        XCTAssertNil(meanDir, "no correction direction when the pack is already mean-centered")
        XCTAssertEqual(identity.count, raw.count)
        for (a, b) in zip(identity, raw) {
            XCTAssertEqual(a, b, "mean_centered pack must pass through bit-identical (no double-correction)")
        }

        // Sanity: the gate matters — with the flag off, the same input IS corrected.
        let (corrected, meanDir2) = EmbeddingCorrection.apply(to: raw, alreadyMeanCentered: false)
        XCTAssertNotNil(meanDir2)
        XCTAssertNotEqual(corrected.first!, raw.first!)
    }

    // MARK: - 3. Recovery widens discrimination and effective dimensionality

    func testRecoveryWidensDiscriminationAndDimensionality() throws {
        let raw = collapsedCorpus(n: 12, dim: 16, alpha: 4)
        let (corrected, meanDir) = EmbeddingCorrection.removeCommonDirection(from: raw)
        let md = try XCTUnwrap(meanDir)

        // Effective dimensionality increases — dead space is recovered.
        let rawDim = EmbeddingCorrection.effectiveDimension(of: raw)
        let corrDim = EmbeddingCorrection.effectiveDimension(of: corrected)
        XCTAssertLessThan(rawDim, 2.0, "collapsed corpus has near-1 effective dimensionality")
        XCTAssertGreaterThan(corrDim, rawDim * 2, "corrected space uses many more dimensions")

        // top1-vs-top10 gap: query == a chunk's own source text (use its vector). The
        // raw gap is tiny (matches the measured 0.018–0.059); after correction (query
        // corrected with the SAME mean) the gap widens dramatically (the measured 2–18×).
        let targetIdx = 3
        let rawQuery = raw[targetIdx]
        let rawScores = raw.map { cosine($0, rawQuery) }.sorted(by: >)
        let rawGap = rawScores[0] - rawScores[min(9, rawScores.count - 1)]

        let correctedQuery = EmbeddingCorrection.center(rawQuery, around: md)
        let corrScores = corrected.map { cosine($0, correctedQuery) }.sorted(by: >)
        let corrGap = corrScores[0] - corrScores[min(9, corrScores.count - 1)]

        XCTAssertLessThan(rawGap, 0.1, "pre-correction: scores are bunched (cannot discriminate)")
        XCTAssertGreaterThan(corrGap, rawGap * 2, "post-correction: discrimination gap widens")
    }

    // MARK: - 4. Query symmetry — own chunk ranks #1 after correction

    func testQueryMatchesItsOwnChunkAtRank1AfterCorrection() throws {
        let raw = collapsedCorpus(n: 12, dim: 16, alpha: 5)
        let (corrected, meanDir) = EmbeddingCorrection.removeCommonDirection(from: raw)
        let md = try XCTUnwrap(meanDir)

        let targetIdx = 7
        let rawQuery = raw[targetIdx]   // query == the chunk's own source text

        // BEFORE: collapsed — the top-1 margin is negligible, so the ranking is not
        // robust (in real embeddings, finite-precision noise within this band reorders
        // results, so the correct chunk is "not retrieved" / ranks low).
        let rawRanking = raw.enumerated()
            .map { ($0.offset, cosine($0.element, rawQuery)) }
            .sorted { $0.1 > $1.1 }
        XCTAssertLessThan(rawRanking[0].1 - rawRanking[1].1, 0.05,
                          "pre-correction: top-1 barely beats top-2 — no real discrimination")

        // AFTER: corrected query (same mean direction) ⇒ the own chunk is rank #1 by a
        // decisive margin — the ranking is now robust.
        let correctedQuery = EmbeddingCorrection.center(rawQuery, around: md)
        let corrRanking = corrected.enumerated()
            .map { ($0.offset, cosine($0.element, correctedQuery)) }
            .sorted { $0.1 > $1.1 }
        XCTAssertEqual(corrRanking[0].0, targetIdx, "post-correction: the own chunk ranks #1")
        XCTAssertGreaterThan(corrRanking[0].1 - corrRanking[1].1, 0.2,
                             "post-correction: rank-1 wins by a clear margin")
    }

    // MARK: - 5. QueryCorrector keeps per-pack means independent (never mixed)

    func testQueryCorrectorIsPerPackAndIndependent() {
        let packA = collapsedCorpus(n: 6, dim: 16, alpha: 3)
        let packB = collapsedCorpus(n: 6, dim: 16, alpha: 3).map { v -> [Float] in
            // Rotate pack B onto a different shared axis so its mean direction differs.
            var r = v; r.swapAt(0, 8); return EmbeddingCorrection.l2Normalized(r)
        }
        let meanA = EmbeddingCorrection.meanDirection(of: packA)!
        let meanB = EmbeddingCorrection.meanDirection(of: packB)!
        XCTAssertLessThan(abs(cosine(meanA, meanB)), 0.2, "the two packs have distinct collapse directions")

        let rawQuery = packA[0]
        let corrector = QueryCorrector(rawQuery: rawQuery, means: ["A": meanA, "B": meanB])

        // The query corrected for pack A must equal center(query, meanA), and for B meanB.
        XCTAssertEqual(corrector.query(for: "A"), EmbeddingCorrection.center(rawQuery, around: meanA))
        XCTAssertEqual(corrector.query(for: "B"), EmbeddingCorrection.center(rawQuery, around: meanB))
        XCTAssertNotEqual(corrector.query(for: "A"), corrector.query(for: "B"), "means must never be mixed")

        // Unknown / nil id ⇒ pass-through (raw query); empty registry ⇒ identity.
        XCTAssertEqual(corrector.query(for: nil), rawQuery)
        XCTAssertEqual(corrector.query(for: "missing"), rawQuery)
        XCTAssertTrue(QueryCorrector(rawQuery: rawQuery, means: [:]).isIdentity)
    }
}
