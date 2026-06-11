// NoesisNoema - Hybrid Routing Runtime
// LocalExecutor - Local LLM execution (on-device RAG + llama.cpp)
// Created: 2026-03-07
// Updated: 2026-05-21 (R1: wired to real RAG pipeline; stub removed per ADR-0008)
// Updated: 2026-05-22 (R2: return retrieved chunks as ExecutionResult.sources)
// Updated: 2026-05-22 (Phase 1: optional DeepSearch retrieval behind a UserDefaults flag)
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

    /// UserDefaults key for the "Deep Search" retrieval setting.
    ///
    /// When `true`, Stage 1 retrieval uses `DeepSearch` (multi-round local
    /// query expansion + MMR) instead of a single-pass `LocalRetriever`.
    /// Off by default — DeepSearch runs several retrieval rounds and is
    /// noticeably heavier; the user opts in via SettingsView ▸ Advanced.
    /// Both retrievers are fully local (no network), so R3's Privacy Step 4.5
    /// guarantee is unaffected by either choice.
    static let deepSearchDefaultsKey = "deepSearchEnabled"

    /// Number of chunks to retrieve, platform-tuned (matches prior v0.3 behavior).
    private var defaultTopK: Int {
        #if os(iOS)
        return 3
        #else
        return 5
        #endif
    }

    /// Stateless overload — delegates to the history-aware path with `[]`.
    /// Empty history ⇒ identical behaviour to pre-ADR-0009.
    func execute(
        query: String,
        sessionId: UUID
    ) async throws -> ExecutionResult {
        #if DEBUG
        print("🧠 [SESSION-MEM/EXEC] LocalExecutor.execute(stateless) entered — delegating with []")
        #endif
        return try await execute(query: query, sessionId: sessionId, history: [])
    }

    /// Execute query using the local LLM + RAG pipeline.
    ///
    /// - Parameters:
    ///   - query: The user's query text
    ///   - sessionId: Session identifier
    ///   - history: Visible prior turns (ADR-0009). Generation-only — does
    ///     NOT influence retrieval (Stage 1) or routing. Empty ⇒ single-turn.
    /// - Returns: ExecutionResult with the generated output
    /// - Throws: ExecutionError on missing model, empty knowledge, or inference failure
    func execute(
        query: String,
        sessionId: UUID,
        history: [ConversationTurn]
    ) async throws -> ExecutionResult {
        #if DEBUG
        print("🧠 [SESSION-MEM/EXEC] LocalExecutor.execute(history-aware) entered; history.count=\(history.count)")
        #endif

        let traceId = UUID()

        print("🔎 [LocalExecutor/RAG] store-state: VectorStore.shared.chunks.count=\(VectorStore.shared.chunks.count)")
        print("🔎 [LocalExecutor/RAG] query: \"\(query.prefix(120))\"")
        print("🔎 [LocalExecutor/RAG] topK=\(defaultTopK), useDeepSearch=\(UserDefaults.standard.bool(forKey: Self.deepSearchDefaultsKey))")

        // Stage 1: Retrieve relevant chunks (local, off main thread).
        // Both retrieval paths are local-only; DeepSearch is opt-in (heavier).
        // ADR-0009 §4: history is NOT a retrieval input — retrieve on the
        // current query only.
        let topK = defaultTopK
        let useDeepSearch = UserDefaults.standard.bool(forKey: Self.deepSearchDefaultsKey)
        let chunks = await Task.detached(priority: .userInitiated) {
            if useDeepSearch {
                var config = DeepSearch.Config()
                config.topK = topK
                return DeepSearch(store: VectorStore.shared, config: config)
                    .retrieve(query: query)
            } else {
                let retriever = LocalRetriever(store: VectorStore.shared)
                return retriever.retrieve(query: query, k: topK, trace: false)
            }
        }.value

        print("🔎 [LocalExecutor/RAG] retrieved chunks.count=\(chunks.count)")
        if let first = chunks.first {
            let preview = first.content.prefix(120).replacingOccurrences(of: "\n", with: " ")
            print("🔎 [LocalExecutor/RAG] chunk[0] preview: \"\(preview)\"")
        } else {
            print("🔎 [LocalExecutor/RAG] no chunks retrieved — context will be empty")
        }

        // Stage 2: Build context from retrieved chunks (current query only).
        let joinedContext = chunks.map { $0.content }.joined(separator: "\n\n")

        // Guard against llama_decode overflow: the whole prompt
        // (system + context + question) must decode within the model's context
        // window, leaving room for the generated answer. Cap the joined context
        // by a char-based estimate (~3 chars/token for English) so it cannot push
        // the prompt past n_ctx. Mirrors the per-platform n_ctx/n_len set in
        // LibLlama.create_context (macOS 4096/1024, iOS 1024/256).
        #if os(iOS)
        let nCtx = 1024, nLen = 256
        #else
        let nCtx = 4096, nLen = 1024
        #endif
        let contextCharCap = max(0, (nCtx - nLen - 200)) * 3
        let context: String
        if joinedContext.count > contextCharCap {
            context = String(joinedContext.prefix(contextCharCap))
            print("✂️ [LocalExecutor/RAG] context truncated \(joinedContext.count)→\(context.count) chars (cap=\(contextCharCap)) to avoid llama_decode overflow")
        } else {
            context = joinedContext
        }

        print("🔎 [LocalExecutor/RAG] context length=\(context.count) chars (chunks joined)")

        // Stage 3: Generate with the local model.
        // currentLLMModel is MainActor-isolated; hop to read it, then call the
        // nonisolated async generate off the main thread.
        let model = await MainActor.run { ModelManager.shared.currentLLMModel }

        let answer: String
        do {
            #if DEBUG
            print("🧠 [SESSION-MEM/EXEC] calling generateAsync with history.count=\(history.count)")
            #endif
            answer = try await model.generateAsync(
                prompt: query,
                context: context.isEmpty ? nil : context,
                history: history
            )
        } catch {
            // ADR-0000: no silent fallback. Surface a structured error.
            throw ExecutionError.inferenceFailed(error.localizedDescription)
        }

        guard !answer.isEmpty else {
            // ADR-0000: do not return placeholder text on empty output.
            throw ExecutionError.emptyOutput
        }

        // R2 (ADR-0008): carry the retrieved chunks out as citations. The same
        // `chunks` already used to build the context above — no extra retrieval.
        return ExecutionResult(
            output: answer,
            sources: chunks,
            traceId: traceId,
            timestamp: Date()
        )
    }
}
