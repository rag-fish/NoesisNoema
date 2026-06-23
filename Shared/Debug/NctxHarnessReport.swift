//
//  NctxHarnessReport.swift
//  NoesisNoema
//
//  Result model + renderers for the n_ctx footprint+latency harness.
//  Produces the ADR-evidence outputs: a clean table (SystemLog + on-screen)
//  and one JSON artifact per run, written to the app's Documents directory
//  (retrievable via Xcode ▸ Devices ▸ Download Container, or the Files app).
//
//  License: MIT License
//

import Foundation

#if DEBUG

struct NctxHarnessReport {
    let selectedNCtx: Int
    let effectiveNCtx: Int
    let modelName: String
    let modelFile: String
    let preset: String
    let embedderName: String
    /// Total chunks in VectorStore at harness start (aggregate across all packs).
    let chunkCount: Int
    /// Per-pack breakdown: (name, chunkCount) pairs, sorted by name.
    /// Populated by the SettingsView caller from DocumentManager.packChunkSummary.
    /// Empty when the harness is invoked without a DocumentManager reference.
    let packSummary: [(name: String, count: Int)]

    let baselineBytes: UInt64
    let loadedPeakBytes: UInt64
    let peakGenBytes: UInt64

    let questions: [String]
    let samples: [NctxLatencySample]

    // MARK: - Derived aggregates (means over non-bailed questions)

    private var answered: [NctxLatencySample] { samples.filter { !$0.bailed } }
    private var bailedCount: Int { samples.filter { $0.bailed }.count }

    private func mean(_ pick: (NctxLatencySample) -> Double) -> Double {
        let xs = answered.map(pick)
        guard !xs.isEmpty else { return 0 }
        return xs.reduce(0, +) / Double(xs.count)
    }

    var meanPromptEvalMs: Double { mean { $0.promptEvalMs } }
    var meanTokensPerSecond: Double { mean { $0.tokensPerSecond } }
    var meanTotalMs: Double { mean { $0.totalMs } }

    private func mb(_ bytes: UInt64) -> Double { Double(bytes) / (1024.0 * 1024.0) }

    var baselineMB: Double { mb(baselineBytes) }
    var loadedMB: Double { mb(loadedPeakBytes) }
    var peakGenMB: Double { mb(peakGenBytes) }

    // MARK: - Table

    func renderTable() -> String {
        var out = ""
        out += "════════════════════════════════════════════════════════════\n"
        out += " n_ctx FOOTPRINT + LATENCY HARNESS\n"
        out += "════════════════════════════════════════════════════════════\n"
        out += " model:    \(modelName)  [\(modelFile)]\n"
        out += " embedder: \(embedderName)   preset: \(preset)\n"
        out += " corpus:   \(chunkCount) total chunks across \(packSummary.count) pack(s)\n"
        if !packSummary.isEmpty {
            for entry in packSummary {
                out += "   \(entry.name)  \(entry.count) chunks\n"
            }
        } else {
            out += "   (pack breakdown not available — pass documentManager.packChunkSummary to run())\n"
        }
        out += " n_ctx requested: \(selectedNCtx)   effective: \(effectiveNCtx)\n"
        out += " questions: \(samples.count)   answered: \(answered.count)   bailed(over-budget): \(bailedCount)\n"
        out += "────────────────────────────────────────────────────────────\n"
        out += " Per-question:\n"
        out += String(format: "  %-3@ %9@ %8@ %10@ %9@ %9@\n",
                      "Q" as NSString, "promptTk" as NSString, "genTk" as NSString,
                      "prefill_ms" as NSString, "tok/s" as NSString, "total_ms" as NSString)
        for (i, s) in samples.enumerated() {
            let tag = s.bailed ? "BAIL" : ""
            out += String(format: "  %-3ld %9ld %8ld %10.1f %9.2f %9.1f  %@\n",
                          i + 1, s.promptTokens, s.genTokens,
                          s.promptEvalMs, s.tokensPerSecond, s.totalMs, tag as NSString)
        }
        out += "────────────────────────────────────────────────────────────\n"
        out += " SUMMARY (means over answered questions):\n"
        out += " n_ctx | baseline | loaded  | peak_gen | prompt_eval_ms | tok/s | total_ms/Q\n"
        out += String(format: " %5ld | %6.1fMB | %6.1fMB | %6.1fMB | %14.1f | %5.2f | %9.1f\n",
                      effectiveNCtx, baselineMB, loadedMB, peakGenMB,
                      meanPromptEvalMs, meanTokensPerSecond, meanTotalMs)
        out += "════════════════════════════════════════════════════════════\n"
        return out
    }

    // MARK: - JSON artifact

    /// Encodable projection (Swift structs above hold non-Codable derived
    /// helpers, so we map to a flat DTO for stable JSON).
    private struct DTO: Encodable {
        struct Q: Encodable {
            let index: Int
            let question: String
            let promptTokens: Int
            let genTokens: Int
            let promptEvalMs: Double
            let decodeMs: Double
            let totalMs: Double
            let tokensPerSecond: Double
            let bailed: Bool
        }
        struct PackEntry: Encodable {
            let name: String
            let chunkCount: Int
        }
        let schema = "nctx-harness/v1"
        let selectedNCtx: Int
        let effectiveNCtx: Int
        let modelName: String
        let modelFile: String
        let preset: String
        let embedderName: String
        /// Aggregate chunk count across all imported packs.
        let chunkCount: Int
        /// Per-pack breakdown. Empty when the harness ran without a DocumentManager reference.
        let packBreakdown: [PackEntry]
        let baselineMB: Double
        let loadedMB: Double
        let peakGenMB: Double
        let meanPromptEvalMs: Double
        let meanTokensPerSecond: Double
        let meanTotalMs: Double
        let answeredCount: Int
        let bailedCount: Int
        let perQuestion: [Q]
    }

    private func makeDTO() -> DTO {
        let perQ: [DTO.Q] = samples.enumerated().map { (i, s) in
            DTO.Q(
                index: i + 1,
                question: i < questions.count ? questions[i] : "",
                promptTokens: s.promptTokens,
                genTokens: s.genTokens,
                promptEvalMs: s.promptEvalMs,
                decodeMs: s.decodeMs,
                totalMs: s.totalMs,
                tokensPerSecond: s.tokensPerSecond,
                bailed: s.bailed
            )
        }
        let breakdown = packSummary.map { DTO.PackEntry(name: $0.name, chunkCount: $0.count) }
        return DTO(
            selectedNCtx: selectedNCtx,
            effectiveNCtx: effectiveNCtx,
            modelName: modelName,
            modelFile: modelFile,
            preset: preset,
            embedderName: embedderName,
            chunkCount: chunkCount,
            packBreakdown: breakdown,
            baselineMB: baselineMB,
            loadedMB: loadedMB,
            peakGenMB: peakGenMB,
            meanPromptEvalMs: meanPromptEvalMs,
            meanTokensPerSecond: meanTokensPerSecond,
            meanTotalMs: meanTotalMs,
            answeredCount: answered.count,
            bailedCount: bailedCount,
            perQuestion: perQ
        )
    }

    /// Writes one JSON file per run to Documents and returns its path (or nil).
    @discardableResult
    func writeJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(makeDTO()) else {
            SystemLog().logEvent(event: "[NctxHarness] ERROR: failed to encode JSON artifact")
            return nil
        }
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        // ISO-ish, filesystem-safe timestamp (no ':').
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = docs.appendingPathComponent("nctx_harness_\(effectiveNCtx)_\(stamp).json")
        do {
            try data.write(to: url, options: .atomic)
            SystemLog().logEvent(event: "[NctxHarness] JSON artifact written: \(url.lastPathComponent)")
            return url.path
        } catch {
            SystemLog().logEvent(event: "[NctxHarness] ERROR writing JSON: \(error.localizedDescription)")
            return nil
        }
    }
}

#endif
