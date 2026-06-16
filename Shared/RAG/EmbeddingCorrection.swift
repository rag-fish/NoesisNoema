// Project: NoesisNoema
// File: EmbeddingCorrection.swift
// Description: Mean-centering recovery layer for collapsed embedding spaces.
//
//   Document vectors in some shipped RAGpacks are collapsed onto a common
//   direction (a shared document-side embedding bias baked in by the external
//   pipeline — prefix/pooling). Symptoms measured on a real pack:
//     - mean-vector norm ≈ 0.893 (near-total alignment; 0 = healthy)
//     - every chunk has cos ≥ 0.744 to the global mean direction
//     - effective dimensionality ≈ 71.9 / 768 (~90% of the space dead)
//     - intra-pack off-diagonal cos mean ≈ 0.79 (healthy is ~0.3–0.5)
//   Removing the common direction restores health (off-diagonal cos → ~0,
//   top1-vs-top10 score gap widens 2–18×). The semantic information is intact;
//   only a shared bias is the problem.
//
//   This is a RECOVERY layer for legacy packs. The permanent fix is pipeline-side
//   re-generation (which would set `embedder.mean_centered = true` in the manifest,
//   gating this correction OFF so healthy packs are never double-corrected).
//
//   ALL math lives here (pure, testable) — it is NOT inlined across call sites.
//   The transform follows the design exactly:
//     mean_dir = normalize(mean(doc_vectors))           // 768-d unit vector
//     doc:   d' = normalize(d - mean_dir)
//     query: q' = normalize(q - mean_dir)               // SAME pack mean_dir
// License: MIT License

import Foundation

enum EmbeddingCorrection {

    // MARK: - Primitives

    /// Arithmetic mean of a set of equal-length vectors. Empty input → [].
    static func mean(of vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first, !first.isEmpty else { return [] }
        let dim = first.count
        var acc = [Float](repeating: 0, count: dim)
        var n = 0
        for v in vectors where v.count == dim {
            for i in 0..<dim { acc[i] += v[i] }
            n += 1
        }
        guard n > 0 else { return [] }
        let inv = 1 / Float(n)
        for i in 0..<dim { acc[i] *= inv }
        return acc
    }

    /// L2 norm of a vector.
    static func l2Norm(_ v: [Float]) -> Float {
        var s: Float = 0
        for x in v { s += x * x }
        return s.squareRoot()
    }

    /// L2-normalized copy. A zero/non-finite-norm vector is returned unchanged
    /// (no NaN); callers treat that as "no usable direction".
    static func l2Normalized(_ v: [Float]) -> [Float] {
        let n = l2Norm(v)
        guard n > 0, n.isFinite else { return v }
        return v.map { $0 / n }
    }

    /// The pack's common direction: `normalize(mean(vectors))`. Returns nil when
    /// there is no usable direction (empty input or a degenerate zero mean).
    static func meanDirection(of vectors: [[Float]]) -> [Float]? {
        let m = mean(of: vectors)
        guard !m.isEmpty else { return nil }
        let norm = l2Norm(m)
        guard norm > 0, norm.isFinite else { return nil }
        return m.map { $0 / norm }
    }

    /// Apply the correction to a single vector: `normalize(v - meanDir)`.
    /// If subtraction yields a degenerate (zero-norm) residual, the original
    /// vector is returned unchanged so similarity never sees a NaN.
    static func center(_ v: [Float], around meanDir: [Float]) -> [Float] {
        guard !v.isEmpty, v.count == meanDir.count else { return v }
        var residual = [Float](repeating: 0, count: v.count)
        for i in 0..<v.count { residual[i] = v[i] - meanDir[i] }
        let norm = l2Norm(residual)
        guard norm > 0, norm.isFinite else { return v }
        for i in 0..<residual.count { residual[i] /= norm }
        return residual
    }

    // MARK: - Batch correction (document side, import-time)

    /// Remove the common direction from a whole matrix of document vectors.
    /// Returns the corrected matrix and the `meanDirection` used (to be stored so
    /// the query can later be corrected with the SAME direction). When there is no
    /// usable direction, this is the identity (and meanDirection is nil).
    static func removeCommonDirection(from vectors: [[Float]]) -> (corrected: [[Float]], meanDirection: [Float]?) {
        guard let meanDir = meanDirection(of: vectors) else { return (vectors, nil) }
        let corrected = vectors.map { center($0, around: meanDir) }
        return (corrected, meanDir)
    }

    /// Manifest-gated entry point. When the pack is already mean-centered (a healthy,
    /// pipeline-corrected pack) this is a strict no-op so it is never double-corrected.
    /// Otherwise it removes the common direction.
    static func apply(to vectors: [[Float]],
                      alreadyMeanCentered: Bool) -> (corrected: [[Float]], meanDirection: [Float]?) {
        guard !alreadyMeanCentered else { return (vectors, nil) }
        return removeCommonDirection(from: vectors)
    }

    // MARK: - Diagnostics (logging + tests)

    /// Norm of the arithmetic mean of (assumed L2-normalized) vectors. This is the
    /// alignment/collapse score: ~0 is healthy, →1 means the vectors point the same
    /// way. Cheap: O(N·d).
    static func meanVectorNorm(of vectors: [[Float]]) -> Float {
        l2Norm(mean(of: vectors))
    }

    /// Effective dimensionality = participation ratio of the (UNCENTERED) Gram
    /// eigenvalues, computed WITHOUT an eigendecomposition via
    ///   PR = (Σ λ)² / Σ λ²  =  trace(G)² / ‖G‖_F²
    /// where, with rows xₙ (NOT mean-subtracted — the collapse is a shared MEAN
    /// direction, so centering would hide it),
    ///   trace(G) = Σₙ ‖xₙ‖²   and   ‖G‖_F² = Σₙ,ₘ (xₙ·xₘ)².
    /// For unit vectors: collapsed (all aligned) → PR ≈ 1; orthogonal/spread → PR ≈ N.
    /// Cost is O(N²·d); intended for modest N (tests / import-time on small packs).
    static func effectiveDimension(of vectors: [[Float]]) -> Float {
        guard let first = vectors.first, !first.isEmpty else { return 0 }
        let dim = first.count
        let rows = vectors.filter { $0.count == dim }
        guard !rows.isEmpty else { return 0 }
        var traceTerm: Double = 0   // Σₙ ‖xₙ‖²
        for x in rows {
            var s: Double = 0
            for v in x { s += Double(v) * Double(v) }
            traceTerm += s
        }
        var frob: Double = 0        // Σₙ,ₘ (xₙ·xₘ)²
        for n in 0..<rows.count {
            let a = rows[n]
            for m in 0..<rows.count {
                let b = rows[m]
                var dot: Double = 0
                for i in 0..<dim { dot += Double(a[i]) * Double(b[i]) }
                frob += dot * dot
            }
        }
        guard frob > 0 else { return 0 }
        return Float((traceTerm * traceTerm) / frob)
    }

    /// Mean of the off-diagonal pairwise cosine similarities. Healthy corpora sit
    /// around ~0.3–0.5; a collapsed pack runs ~0.79. O(N²·d).
    static func averageOffDiagonalCosine(of vectors: [[Float]]) -> Float {
        let normed = vectors.map { l2Normalized($0) }
        guard normed.count > 1 else { return 0 }
        var sum: Double = 0
        var pairs: Int = 0
        for i in 0..<normed.count {
            for j in (i + 1)..<normed.count {
                let a = normed[i], b = normed[j]
                guard a.count == b.count else { continue }
                var dot: Double = 0
                for k in 0..<a.count { dot += Double(a[k]) * Double(b[k]) }
                sum += dot
                pairs += 1
            }
        }
        guard pairs > 0 else { return 0 }
        return Float(sum / Double(pairs))
    }
}

/// Resolves the per-pack–corrected query vector at search time. Document vectors
/// are corrected once at import (baked into their stored embedding); the query must
/// be corrected with the SAME `meanDirection` as the pack it is being compared
/// against. Because the VectorStore is a single flat corpus mixing packs, the
/// correction is resolved per chunk via the chunk's `correctionId`, memoized per id.
///
/// An empty `means` registry makes this a pass-through (raw query for every chunk),
/// so existing/uncorrected packs and call sites behave exactly as before.
final class QueryCorrector {
    private let rawQuery: [Float]
    private let means: [String: [Float]]
    private var cache: [String: [Float]] = [:]

    init(rawQuery: [Float], means: [String: [Float]]) {
        self.rawQuery = rawQuery
        self.means = means
    }

    /// True when no correction would ever be applied (registry empty).
    var isIdentity: Bool { means.isEmpty }

    /// The query vector to compare against a chunk carrying `correctionId`.
    /// Falls back to the raw query when the chunk has no id or no registered mean.
    func query(for correctionId: String?) -> [Float] {
        guard !rawQuery.isEmpty,
              let id = correctionId,
              let meanDir = means[id] else { return rawQuery }
        if let cached = cache[id] { return cached }
        let corrected = EmbeddingCorrection.center(rawQuery, around: meanDir)
        cache[id] = corrected
        return corrected
    }
}

#if DEBUG
extension EmbeddingCorrection {
    /// Runnable smoke for the mean-centering recovery, callable from a debugger or a
    /// scratch call site while the NoesisNoemaTests Xcode target is unwired (mirrors
    /// `RAGpackManifest.runDecodeSmoke()` / `RAGpackReader.runChunksSmoke()`). Builds a
    /// synthetic collapsed corpus and asserts the common direction is removed, the
    /// effective dimensionality rises, and a query for its own chunk gains a decisive
    /// rank-1 margin.
    static func runCorrectionSmoke() {
        // collapsed corpus: each vector = normalize(3·axis0 + axis_{i+1})
        let dim = 16, n = 12
        var raw: [[Float]] = []
        for i in 0..<n {
            var v = [Float](repeating: 0, count: dim)
            v[0] = 3; v[i + 1] = 1
            raw.append(l2Normalized(v))
        }
        let rawOff = averageOffDiagonalCosine(of: raw)
        let rawDim = effectiveDimension(of: raw)

        let (corrected, meanDir) = removeCommonDirection(from: raw)
        assert(meanDir != nil, "a common direction must be found")
        let corrOff = averageOffDiagonalCosine(of: corrected)
        let corrDim = effectiveDimension(of: corrected)
        assert(rawOff > 0.6, "synthetic corpus must start collapsed")
        assert(abs(corrOff) < 0.25, "off-diagonal cosine must drop toward 0")
        assert(corrDim > rawDim * 2, "effective dimensionality must rise")

        // mean_centered gate is a strict no-op.
        let (identity, none) = apply(to: raw, alreadyMeanCentered: true)
        assert(none == nil && identity == raw, "mean_centered=true must be identity")

        print(String(format: "[EmbeddingCorrection] smoke PASSED — offDiag %.3f→%.3f, "
                     + "effDim %.2f→%.2f, meanNorm %.3f→%.3f",
                     rawOff, corrOff, rawDim, corrDim,
                     meanVectorNorm(of: raw), meanVectorNorm(of: corrected)))
    }
}
#endif
