//
//  NctxHarnessProbe.swift
//  NoesisNoema
//
//  Collection sink for the n_ctx footprint+latency harness. The unified
//  inference pipeline (`runNoesisCompletion`) feeds per-question timing and a
//  "both models resident" footprint snapshot into this singleton, and a
//  background `MemorySampler` tracks the true peak across the whole run.
//
//  Everything here is DEBUG-only and inert unless the harness explicitly calls
//  `begin()`. During normal app use `active == false`, so every feed method is
//  a cheap early-return — no behavioural or performance impact on shipping
//  generation paths.
//
//  License: MIT License
//

import Foundation

#if DEBUG

/// One question's latency record.
struct NctxLatencySample {
    /// Prefill / time-to-first-token: duration of `completion_init`, which runs
    /// the single `llama_decode` over the whole RAG+history+question prompt.
    let promptEvalMs: Double
    /// Decode wall-clock: the token-generation loop only.
    let decodeMs: Double
    /// Total wall-clock for the answer (prompt build → cleaned answer).
    let totalMs: Double
    /// Generated (decoded) token count.
    let genTokens: Int
    /// Prompt token count (n_cur right after `completion_init`).
    let promptTokens: Int
    /// True when `completion_init` bailed (prompt + n_len > n_ctx). Such a
    /// question produced no tokens; it is excluded from latency means but
    /// counted so the table shows where a level overflows.
    let bailed: Bool

    /// Decode throughput (tokens/sec). 0 for bailed/zero-token questions.
    var tokensPerSecond: Double {
        guard decodeMs > 0, genTokens > 0 else { return 0 }
        return Double(genTokens) / (decodeMs / 1000.0)
    }
}

/// DEBUG-only collection sink. Thread-safe (NSLock) — the pipeline feeds it
/// from a background task while the harness reads it from the MainActor runner.
final class NctxHarnessProbe: @unchecked Sendable {
    static let shared = NctxHarnessProbe()
    private init() {}

    private let lock = NSLock()
    private var _active = false
    private var samples: [NctxLatencySample] = []
    private var loadedFootprintPeakBytes: UInt64 = 0
    private var lastEffectiveNCtx: Int = 0

    var active: Bool {
        lock.lock(); defer { lock.unlock() }
        return _active
    }

    /// Arm collection for one harness level. Clears prior samples.
    func begin() {
        lock.lock()
        _active = true
        samples = []
        loadedFootprintPeakBytes = 0
        lastEffectiveNCtx = 0
        lock.unlock()
    }

    /// Disarm and return everything collected during this level.
    func end() -> (samples: [NctxLatencySample], loadedPeakBytes: UInt64, effectiveNCtx: Int) {
        lock.lock(); defer { lock.unlock() }
        _active = false
        return (samples, loadedFootprintPeakBytes, lastEffectiveNCtx)
    }

    /// Called by the pipeline right after `create_context` succeeds, when the
    /// generator KV cache is freshly allocated and the embedder is already
    /// resident (retrieval ran first). Records the effective n_ctx and the
    /// "both models loaded" footprint (peak across the run's questions).
    func noteContextCreated(effectiveNCtx: Int) {
        lock.lock(); defer { lock.unlock() }
        guard _active else { return }
        lastEffectiveNCtx = effectiveNCtx
        if let f = MemoryFootprint.currentBytes(), f > loadedFootprintPeakBytes {
            loadedFootprintPeakBytes = f
        }
    }

    /// Called by the pipeline once per question with its latency record.
    func recordGeneration(_ sample: NctxLatencySample) {
        lock.lock(); defer { lock.unlock() }
        guard _active else { return }
        samples.append(sample)
    }
}

/// Background peak-footprint sampler. Polls `phys_footprint` on its own queue so
/// the true peak during a generation run is not missed between coarse markers.
final class MemorySampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "noesis.nctx.memsampler", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private var _peakBytes: UInt64 = 0

    var peakBytes: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return _peakBytes
    }

    var peakMB: Double { Double(peakBytes) / (1024.0 * 1024.0) }

    /// Start polling every `intervalMs` (default 150ms). Resets the peak.
    func start(intervalMs: Int = 150) {
        stop()
        lock.lock(); _peakBytes = 0; lock.unlock()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(intervalMs), leeway: .milliseconds(20))
        t.setEventHandler { [weak self] in
            guard let self, let f = MemoryFootprint.currentBytes() else { return }
            self.lock.lock()
            if f > self._peakBytes { self._peakBytes = f }
            self.lock.unlock()
        }
        t.resume()
        timer = t
    }

    /// Take one immediate sample (e.g. to fold a known spike into the peak).
    func sampleNow() {
        guard let f = MemoryFootprint.currentBytes() else { return }
        lock.lock()
        if f > _peakBytes { _peakBytes = f }
        lock.unlock()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}

#endif
