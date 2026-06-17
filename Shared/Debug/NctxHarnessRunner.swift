//
//  NctxHarnessRunner.swift
//  NoesisNoema
//
//  DEBUG-only orchestrator for the n_ctx footprint + latency harness.
//
//  Drives a fixed 5-question Spinoza/Ethics RAG run through the REAL on-device
//  local path (`LocalExecutor` → `LLMModel.generateAsync` → `runNoesisCompletion`),
//  while:
//    - sampling `phys_footprint` continuously (peak across the whole run),
//    - collecting per-question prefill / decode / total latency via
//      `NctxHarnessProbe`,
//  then emits a clean table to SystemLog + on-screen and writes one JSON
//  artifact per run. The user runs this four times (n_ctx = 1024/2048/4096/8192)
//  via the DEBUG picker; only n_ctx varies between runs.
//
//  This is measurement scaffolding only — it changes no retrieval, sampling, or
//  generation logic, and is excluded from Release. It calls `LocalExecutor`
//  directly (not the policy-routed coordinator) to guarantee the on-device path
//  is what gets measured.
//
//  License: MIT License
//

import Foundation

#if DEBUG && !BRIDGE_TEST

@MainActor
final class NctxHarnessRunner: ObservableObject {

    /// Fixed 5-question battery over the Ethics RAGpack. Held constant across
    /// all four n_ctx runs so only n_ctx varies (guardrail).
    static let questions: [String] = [
        "What does Spinoza mean by substance, and why can there be only one?",
        "How does Spinoza define God, and how does God relate to Nature?",
        "What is the conatus, and what role does it play in Spinoza's ethics?",
        "Explain the distinction between adequate and inadequate ideas.",
        "According to Spinoza, how does one attain freedom and blessedness?"
    ]

    @Published var isRunning = false
    @Published var progressText = ""
    /// Human-readable result table for on-screen display once a run completes.
    @Published var resultText: String?
    /// Path of the JSON artifact written for the most recent run.
    @Published var lastArtifactPath: String?

    private let localExecutor = LocalExecutor()

    // MARK: - Run

    func run() {
        guard !isRunning else { return }
        isRunning = true
        resultText = nil
        lastArtifactPath = nil
        progressText = "Preparing…"

        let selectedNCtx = NctxConfig.deviceNCtx

        Task { @MainActor in
            let report = await self.execute(selectedNCtx: selectedNCtx)
            self.resultText = report.renderTable()
            self.lastArtifactPath = report.writeJSON()
            SystemLog().logEvent(event: "[NctxHarness] RUN COMPLETE\n" + report.renderTable())
            self.progressText = "Done."
            self.isRunning = false
        }
    }

    private func execute(selectedNCtx: Int32) async -> NctxHarnessReport {
        let sampler = MemorySampler()
        let probe = NctxHarnessProbe.shared

        // (a) Baseline idle footprint — sampled before the run warms anything.
        let baselineBytes = MemoryFootprint.currentBytes() ?? 0

        let modelName = ModelManager.shared.currentLLMModel.name
        let modelFile = ModelManager.shared.currentLLMModel.modelFile
        let preset = ModelManager.shared.currentLLMPreset
        let embedderName = ModelManager.shared.currentEmbeddingModel.name
        let chunkCount = VectorStore.shared.chunks.count

        probe.begin()
        sampler.start(intervalMs: 150)

        // Mirror the chat path: accumulate capped (last-3) history across turns.
        var history: [ConversationTurn] = []
        let sessionId = UUID()

        for (i, q) in Self.questions.enumerated() {
            progressText = "Q\(i + 1)/\(Self.questions.count)…"
            do {
                let result = try await localExecutor.execute(
                    query: q,
                    sessionId: sessionId,
                    history: history
                )
                // Fold the answer into history (3-turn cap, matching the UI).
                history.append(ConversationTurn(question: q, answer: result.output, date: Date()))
                if history.count > SessionMemory.defaultMaxTurns {
                    history.removeFirst(history.count - SessionMemory.defaultMaxTurns)
                }
            } catch {
                // A bail (over-budget) surfaces here as an ExecutionError; the
                // probe still recorded the bailed sample from the pipeline.
                SystemLog().logEvent(event: "[NctxHarness] Q\(i + 1) error: \(error.localizedDescription)")
            }
            // Fold any momentary post-question spike into the peak.
            sampler.sampleNow()
        }

        sampler.stop()
        let (samples, loadedPeakBytes, effectiveNCtx) = probe.end()

        return NctxHarnessReport(
            selectedNCtx: Int(selectedNCtx),
            effectiveNCtx: effectiveNCtx,
            modelName: modelName,
            modelFile: modelFile,
            preset: preset,
            embedderName: embedderName,
            chunkCount: chunkCount,
            baselineBytes: baselineBytes,
            loadedPeakBytes: loadedPeakBytes,
            peakGenBytes: sampler.peakBytes,
            questions: Self.questions,
            samples: samples
        )
    }
}

#endif
