// NoesisNoema - Hybrid Routing Runtime
// LocalExecutor - Local LLM execution (on-device RAG + llama.cpp)
// Created: 2026-03-07
// Updated: 2026-05-21 (R1: wired to real RAG pipeline; stub removed per ADR-0008)
// License: MIT License

import Foundation

/// Local Executor
///
/// Executes queries using the on-device RAG + llama.cpp pipeline:
///   retrieve (VectorStore) -> build context -> generate (LLMModel) -> result.
///
/// Constitutional Constraints (ADR-0000):
/// - MUST NOT make routing decisions
/// - MUST NOT change execution path
/// - MUST NOT perform silent fallback   <- failures are thrown, never stubbed
/// - MUST NOT contain routing logic
/// - MUST NOT mutate global state
/// - MUST NOT retry automatically
///
/// Privacy (ADR-0008 Decision 4 / execution-flow.md Step 4.5):
/// - This path performs no network I/O. Retrieval is local (VectorStore) and
///   inference is local (llama.cpp). Enforcement of the network cutoff is
///   tracked in R3 and verified by UAT U2.
final class LocalExecutor: Executor {

    /// Number of chunks to retrieve, platform-tuned (matches prior v0.3 behavior).
    private var defaultTopK: Int {
        #if os(iOS)
        return 3
        #else
        return 5
        #endif
    }

    /// Execute query using the local LLM + RAG pipeline.
    ///
    /// - Parameters:
    ///   - query: The user's query text
    ///   - sessionId: Session identifier
    /// - Returns: ExecutionResult with the generated output
    /// - Throws: ExecutionError on missing model, empty knowledge, or inference failure
    func execute(
        query: String,
        sessionId: UUID
    ) async throws -> ExecutionResult {

        let traceId = UUID()

        // Stage 1: Retrieve relevant chunks (local, off main thread).
        let topK = defaultTopK
        let chunks = await Task.detached(priority: .userInitiated) {
            let retriever = LocalRetriever(store: VectorStore.shared)
            return retriever.retrieve(query: query, k: topK, trace: false)
        }.value

        // Stage 2: Build context from retrieved chunks.
        let context = chunks.map { $0.content }.joined(separator: "\n\n")

        // Stage 3: Generate with the local model.
        // currentLLMModel is MainActor-isolated; hop to read it, then call the
        // nonisolated async generate off the main thread.
        let model = await MainActor.run { ModelManager.shared.currentLLMModel }

        let answer: String
        do {
            answer = try await model.generateAsync(
                prompt: query,
                context: context.isEmpty ? nil : context
            )
        } catch {
            // ADR-0000: no silent fallback. Surface a structured error.
            throw ExecutionError.inferenceFailed(error.localizedDescription)
        }

        guard !answer.isEmpty else {
            // ADR-0000: do not return placeholder text on empty output.
            throw ExecutionError.emptyOutput
        }

        return ExecutionResult(
            output: answer,
            traceId: traceId,
            timestamp: Date()
        )
    }
}
