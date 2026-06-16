// Project: NoesisNoema
// File: RetrievalUAT.swift
// Description: Logic-level User Acceptance Test proving the mean-centering recovery
//   (merged PR #113) actually restored retrieval quality on a REAL, healthy pack.
//
//   This drives the production retrieval stack directly — RAGpackReader (import-time
//   mean-centering) → VectorStore (query-time correction + cosine search) — with the
//   REAL llama.cpp embedder loaded from the host app bundle. NO UI automation, NO
//   network. Each test imports the fixture from scratch (UAT-from-scratch rule) into
//   a fresh VectorStore so no singleton / persisted state leaks between assertions.
//
//   Fixture: ragpack_ethics_FIXED_2026-06-16.zip — the regenerated healthy pack
//   (417 pymupdf-extracted readable chunks, manifest mean_centered:false, so the
//   app's import-time correction runs). Bundled as a test resource.
//
//   The four assertions (see ADR-0011 / docs/audit retrieval root-cause):
//     1. Import health    — pre-correction mean-vector norm ≈ 0.89 (the pathology),
//        post-correction < 0.5, correctionMean registered, chunk text readable.
//     2. Content-discrimination (THE killer test) — 5 distinct queries must NOT all
//        return the same top-1 chunk (the broken pack returned ONE chunk for every
//        query). |{top-1 ids}| >= 4.
//     3. Query == source text → rank 1 (asymmetric-correctness proof).
//     4. 5-question semantic UAT — query → expected marker in the top result.
//
//   Evidence: writes uat_results.json to the test output dir and prints a
//   human-readable summary table to the test log.
// License: MIT License

import XCTest
@testable import NoesisNoema

final class RetrievalUAT: XCTestCase {

    // MARK: - Fixture / shared embedder (loaded once; GGUF load is expensive)

    /// Result of importing the FIXED pack through the real RAGpackReader path and
    /// registering it into a fresh VectorStore exactly as DocumentManager does.
    private struct ImportedPack {
        let store: VectorStore
        let docName: String
        let chunks: [Chunk]
        let correctionMean: [Float]?
        let preNorm: Float      // mean-vector norm of the RAW (pre-correction) doc vectors
        let postNorm: Float     // mean-vector norm AFTER import-time mean-centering
    }

    private static let packResource = "ragpack_ethics_FIXED_2026-06-16"

    /// Shared embedder, loaded once from the host app bundle. nil + reason when the
    /// embedder GGUF is unavailable (so every test emits a clear XCTSkip, not a crash).
    private static let sharedEmbedder: EmbeddingModel? = {
        let m = EmbeddingModel(name: "uat")
        return m.dimension > 0 ? m : nil
    }()

    /// Thread-safe collector for the machine-readable evidence file.
    private struct ResultRecord: Codable {
        let test_id: String
        let pass: Bool
        let metric_name: String
        let metric_value: Double
        let expected: String
    }
    private static let resultsLock = NSLock()
    private static var results: [ResultRecord] = []
    private static func record(_ r: ResultRecord) {
        resultsLock.lock(); defer { resultsLock.unlock() }
        results.append(r)
    }

    private static var summaryLines: [String] = []
    private static func summary(_ line: String) {
        resultsLock.lock(); defer { resultsLock.unlock() }
        summaryLines.append(line)
        print(line)
    }

    // MARK: - Setup

    override func setUpWithError() throws {
        try XCTSkipIf(Self.sharedEmbedder == nil,
                      "Embedder GGUF '\(EmbeddingModel.embedderResourceName).\(EmbeddingModel.embedderResourceExt)' "
                      + "not loadable from the host app bundle — UAT requires the real embedder.")
    }

    // MARK: - Real import path: RAGpackReader → (DocumentManager-equivalent registration)

    /// Imports the bundled FIXED pack through the production RAGpackReader (which runs
    /// import-time mean-centering and validates the manifest against the LIVE embedder),
    /// then registers the corrected chunks into a FRESH VectorStore exactly as
    /// DocumentManager.processRAGpackImport does (tags each chunk's correctionId and
    /// registers the pack's correctionMean). Returns everything the assertions need.
    private func importFIXEDPack() throws -> ImportedPack {
        let embedder = try XCTUnwrap(Self.sharedEmbedder, "embedder must be loaded")

        // 1. Locate + unzip the bundled fixture into a fresh temp dir (mirrors the
        //    unzip step DocumentManager performs before handing the dir to the reader).
        let bundle = Bundle(for: Self.self)
        let zipURL = try XCTUnwrap(
            bundle.url(forResource: Self.packResource, withExtension: "zip"),
            "fixture \(Self.packResource).zip is not bundled into the test target")
        let dir = try Self.unzipToTemp(zipURL)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 2. Pre-correction mean-vector norm — computed from the RAW embeddings.npy the
        //    reader is about to read, so we can assert the pathology was present.
        let npyURL = dir.appendingPathComponent("embeddings.npy")
        let (shape, flat) = try NumpyReader.readFloat32(from: npyURL)
        XCTAssertEqual(shape.count, 2, "embeddings.npy must be 2-D")
        let rowCount = shape[0], dim = shape[1]
        var raw: [[Float]] = []
        raw.reserveCapacity(rowCount)
        for r in 0..<rowCount { raw.append(Array(flat[(r*dim)..<((r+1)*dim)])) }
        let preNorm = EmbeddingCorrection.meanVectorNorm(of: raw)

        // 3. REAL reader path: validates manifest against the live embedder, applies
        //    import-time mean-centering, returns corrected chunks + correctionMean.
        let (chunks, corrected, correctionMean) =
            try RAGpackReader.readPack(at: dir, embedder: embedder)
        let postNorm = EmbeddingCorrection.meanVectorNorm(of: corrected)

        // 4. Register into a FRESH VectorStore exactly as DocumentManager does: title
        //    the chunks, tag correctionId so the query is corrected with this pack's
        //    mean at search time, and register the pack's correctionMean.
        let docName = "\(Self.packResource)_uat"
        let titled = chunks.map { ch -> Chunk in
            var c = ch
            if c.sourceTitle == nil { c.sourceTitle = docName }
            if correctionMean != nil { c.correctionId = docName }
            return c
        }
        let store = VectorStore(embeddingModel: embedder)
        store.addChunks(titled, deduplicate: false)
        if let cm = correctionMean { store.correctionMeans[docName] = cm }

        return ImportedPack(store: store, docName: docName, chunks: titled,
                            correctionMean: correctionMean, preNorm: preNorm, postNorm: postNorm)
    }

    /// Unzips `zipURL` into a unique temp directory using `/usr/bin/unzip` (keeps the
    /// test target free of a ZIPFoundation dependency; macOS-only, which this UAT is).
    private static func unzipToTemp(_ zipURL: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("uat-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-o", "-q", zipURL.path, "-d", dir.path]
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "RetrievalUAT", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "unzip failed for \(zipURL.lastPathComponent)"])
        }
        // Some packs nest a top-level folder; normalize to the dir holding manifest.json.
        if !FileManager.default.fileExists(atPath: dir.appendingPathComponent("manifest.json").path),
           let sub = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                        .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }) {
            return sub
        }
        return dir
    }

    private static func whitespaceRatio(_ s: String) -> Double {
        guard !s.isEmpty else { return 0 }
        let ws = s.unicodeScalars.filter { CharacterSet.whitespacesAndNewlines.contains($0) }.count
        return Double(ws) / Double(s.unicodeScalars.count)
    }

    // MARK: - Test 1: Import health

    func test1_importHealth() throws {
        let pack = try importFIXEDPack()

        // 1a. Pre-correction pathology: mean-vector norm ≈ 0.89.
        Self.record(.init(test_id: "1a_pre_correction_mean_norm", pass: abs(pack.preNorm - 0.89) <= 0.1,
                          metric_name: "pre_correction_mean_vector_norm",
                          metric_value: Double(pack.preNorm), expected: "≈0.89 (±0.1)"))
        XCTAssertEqual(pack.preNorm, 0.89, accuracy: 0.1,
                       "pre-correction mean-vector norm should show the collapse pathology (~0.89)")

        // 1b. Post-correction recovery: mean-vector norm < 0.5.
        Self.record(.init(test_id: "1b_post_correction_mean_norm", pass: pack.postNorm < 0.5,
                          metric_name: "post_correction_mean_vector_norm",
                          metric_value: Double(pack.postNorm), expected: "<0.5"))
        XCTAssertLessThan(pack.postNorm, 0.5,
                          "post-correction mean-vector norm must collapse toward 0 (recovery)")

        // 1c. correctionMean registered for the pack in the VectorStore.
        let registered = pack.correctionMean != nil
            && pack.store.correctionMeans[pack.docName] != nil
            && (pack.store.correctionMeans[pack.docName]?.count ?? 0) > 0
        Self.record(.init(test_id: "1c_correction_registered", pass: registered,
                          metric_name: "correction_means_registered_for_pack",
                          metric_value: registered ? 1 : 0, expected: "==1"))
        XCTAssertTrue(registered, "the pack's correctionMean must be registered in VectorStore.correctionMeans")

        // 1d. Chunk text is readable (guards against re-importing a broken pack): a
        //     sampled substantive chunk has whitespace ratio in [0.10, 0.20].
        let sample = pack.chunks[pack.chunks.count / 2].content
        let wsr = Self.whitespaceRatio(sample)
        let readable = wsr >= 0.10 && wsr <= 0.20
        Self.record(.init(test_id: "1d_chunk_readable", pass: readable,
                          metric_name: "sample_chunk_whitespace_ratio",
                          metric_value: wsr, expected: "0.10–0.20"))
        XCTAssertTrue(readable, "sampled chunk whitespace ratio \(wsr) outside readable band 0.10–0.20")

        Self.summary(String(format: "[T1] import health: preNorm=%.3f (≈0.89) postNorm=%.3f (<0.5) "
                            + "registered=%@ wsRatio=%.3f chunks=%d",
                            pack.preNorm, pack.postNorm, registered ? "YES" : "NO", wsr, pack.chunks.count))
    }

    // MARK: - Test 2: Content-discrimination (THE killer test)

    func test2_contentDiscrimination() throws {
        let pack = try importFIXEDPack()
        let queries = [
            "the nature and existence of God as infinite substance",
            "the human mind and the body that is its object",
            "the origin and strength of the emotions and affects",
            "human bondage and the power of the passions over reason",
            "human freedom, blessedness, and the intellectual love of God",
        ]
        var topIds: [String] = []
        Self.summary("[T2] content-discrimination — top-1 chunk per query:")
        for q in queries {
            let top = pack.store.retrieveChunks(for: q, topK: 1).first
            let id = top.map { Self.chunkKey($0) } ?? "<none>"
            topIds.append(id)
            Self.summary("    q=\"\(q.prefix(46))…\" → \(Self.snippet(top))")
        }
        let distinct = Set(topIds).count
        Self.record(.init(test_id: "2_distinct_top1", pass: distinct >= 4,
                          metric_name: "distinct_top1_ids_over_5_queries",
                          metric_value: Double(distinct), expected: ">=4"))
        XCTAssertGreaterThanOrEqual(distinct, 4,
            "fixed+corrected pack must NOT return the same chunk for every query (got \(distinct)/5 distinct)")
        Self.summary("[T2] distinct top-1 chunks = \(distinct)/5 (expected >= 4)")
    }

    // MARK: - Test 3: Query == source text → rank 1 (asymmetric-correctness proof)

    func test3_querySourceTextRanksFirst() throws {
        let pack = try importFIXEDPack()
        // 3 distinct, substantive chunks spread across the corpus (avoid front-matter).
        let targetIdxs = [pack.chunks.count / 4, pack.chunks.count / 2, (pack.chunks.count * 3) / 4]
        var rank1Hits = 0
        Self.summary("[T3] query == chunk source text → expected rank 1:")
        for idx in targetIdxs {
            let source = pack.chunks[idx]
            let top = pack.store.retrieveChunks(for: source.content, topK: 1).first
            let hit = top.map { $0.content == source.content } ?? false
            if hit { rank1Hits += 1 }
            Self.summary("    chunk #\(idx) self-query → rank1=\(hit ? "YES" : "NO") top=\(Self.snippet(top))")
        }
        Self.record(.init(test_id: "3_self_query_rank1", pass: rank1Hits == targetIdxs.count,
                          metric_name: "self_query_rank1_hits",
                          metric_value: Double(rank1Hits), expected: "==\(targetIdxs.count)"))
        XCTAssertEqual(rank1Hits, targetIdxs.count,
            "every chunk's own source text must retrieve that chunk at rank 1 (got \(rank1Hits)/\(targetIdxs.count))")
        Self.summary("[T3] rank-1 self-retrieval = \(rank1Hits)/\(targetIdxs.count)")
    }

    // MARK: - Test 4: 5-question semantic UAT

    func test4_semanticUAT() throws {
        let pack = try importFIXEDPack()
        // query → expected marker (case-insensitive substring) keyed to the Ethics
        // structure: Part I God, Part II Mind, Part III Emotions, Part IV Bondage,
        // Part V Freedom / Power of the Intellect.
        let pairs: [(q: String, marker: String)] = [
            ("Concerning God: God is an absolutely infinite being or substance", "god"),
            ("Of the nature and origin of the human mind and its ideas", "mind"),
            ("On the origin and nature of the emotions, desire, pleasure and pain", "emotion"),
            // This edition titles Part IV "OF HUMAN SERVITUDE, OR THE STRENGTH OF THE
            // EMOTIONS" — the query says "bondage", the text says "servitude": a
            // lexical-independent semantic match is exactly what we want to prove.
            ("Of human bondage: the strength of the emotions over a person", "servitude"),
            ("Of human freedom and the power of the intellect; blessedness", "intellect"),
        ]
        var hits = 0
        Self.summary("[T4] 5-question semantic UAT (query → expected marker → top chunk):")
        for (q, marker) in pairs {
            let top = pack.store.retrieveChunks(for: q, topK: 1).first
            let text = (top?.content ?? "").lowercased()
            let hit = text.contains(marker.lowercased())
            if hit { hits += 1 }
            Self.record(.init(test_id: "4_marker[\(marker)]", pass: hit,
                              metric_name: "top1_contains_marker",
                              metric_value: hit ? 1 : 0, expected: "contains \"\(marker)\""))
            Self.summary("    q=\"\(q.prefix(40))…\" marker=\"\(marker)\" hit=\(hit ? "YES" : "NO") top=\(Self.snippet(top))")
            XCTAssertTrue(hit, "query \"\(q)\" top result should contain marker \"\(marker)\"")
        }
        Self.summary("[T4] semantic marker hits = \(hits)/\(pairs.count)")
    }

    // MARK: - Helpers (chunk identity + display)

    /// Stable identity for a chunk: its char span when present, else a content hash.
    private static func chunkKey(_ c: Chunk) -> String {
        if let s = c.charStart, let e = c.charEnd { return "\(c.docId ?? "doc"):\(s)-\(e)" }
        return "h\(c.content.hashValue)"
    }

    private static func snippet(_ c: Chunk?) -> String {
        guard let c = c else { return "<none>" }
        let flat = c.content.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let body = flat.count > 70 ? String(flat.prefix(70)) + "…" : flat
        return "[\(chunkKey(c))] \(body)"
    }

    // MARK: - Evidence output (runs after all tests in this class)

    override class func tearDown() {
        defer { super.tearDown() }
        resultsLock.lock()
        let records = results
        let lines = summaryLines
        resultsLock.unlock()
        guard !records.isEmpty else { return }

        // Resolve a WRITABLE output dir. The host app is sandboxed, so the bundle /
        // build dirs are read-only; the sandbox container's temp dir is the correct
        // "test output dir". Honor UAT_OUTPUT_DIR when it points somewhere writable.
        let fm = FileManager.default
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? enc.encode(records)) ?? Data()
        var candidates: [URL] = []
        if let env = ProcessInfo.processInfo.environment["UAT_OUTPUT_DIR"] {
            candidates.append(URL(fileURLWithPath: env, isDirectory: true))
        }
        candidates.append(fm.temporaryDirectory)
        var written: String? = nil
        for dir in candidates {
            let url = dir.appendingPathComponent("uat_results.json")
            do { try data.write(to: url, options: .atomic); written = url.path; break }
            catch { continue }
        }
        print("\n[UAT] evidence written: \(written ?? "<failed>")")

        print("\n================= RETRIEVAL UAT SUMMARY =================")
        for l in lines { print(l) }
        let passed = records.filter { $0.pass }.count
        print(String(format: "RESULT: %d/%d assertions passed", passed, records.count))
        print("========================================================\n")
    }
}
