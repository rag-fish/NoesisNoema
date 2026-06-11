---
date: 2026-06-12
author: claude-code
pr_context: post-#104 UAT (VectorStore always empty)
scope: read-only investigation
---

# VectorStore populate gap — why `VectorStore.shared.chunks.count=0` at query time

**TL;DR:** `PersistenceStore.loadRAGpackChunks()` loads the persisted RAGpack into
`DocumentManager.ragpackChunks` (an in-memory dictionary), but **nothing ever copies
those chunks into `VectorStore.shared.chunks`**. The only app-lifecycle write to
`VectorStore.shared.chunks` happens inside the live *import* path
(`DocumentManager.processRAGpackImport`, `DocumentManager.swift:216`). On a normal
launch — where the pack is loaded from disk, not freshly imported — that write never
runs, so the retrieval store the executor queries (`VectorStore.shared`) stays empty.
This is a wiring gap, not a retrieval or embedding bug.

---

## Section 1 — Locate VectorStore and its public interface

`Shared/RAG/VectorStore.swift`. It is a **plain `class`** (reference type, **not** an
actor, **not** `@MainActor`, no internal locking on `chunks`). The `shared` singleton
is a `static let`.

Type declaration and chunk storage — `Shared/RAG/VectorStore.swift:9-32`:

```swift
class VectorStore {
    // ...
    var chunks: [Chunk]
    var embeddingModel: EmbeddingModel
    var isEmbedded: Bool

    private var chunkCache: [String: [Chunk]] = [:]
    private let cacheQueue = DispatchQueue(label: "com.noesis.vectorstore.cache", attributes: .concurrent)

    init(embeddingModel: EmbeddingModel, chunks: [Chunk] = []) {
        self.embeddingModel = embeddingModel
        self.chunks = chunks
        self.isEmbedded = false
    }
```

The singleton — `Shared/RAG/VectorStore.swift:203-204`:

```swift
    /// VectorStoreのシングルトン（RAG検索対象チャンクを保持）
    static let shared = VectorStore(embeddingModel: EmbeddingModel(name: "default-embedding"))
```

**Public mutating methods that add chunks** (`VectorStore.swift:39-89`):

| Method | Lines | Behavior |
|---|---|---|
| `addTexts(_:deduplicate:)` | 39-48 | Embeds each string, then calls `addChunks`. |
| `addChunks(_:deduplicate:)` | 51-65 | Appends chunks (optionally de-duped by `content` + `embedding`). |
| `clear()` | 68 | `chunks.removeAll()`. |
| `reembedAll()` | 71-76 | Re-embeds existing chunks in place (does not add). |
| `load(from:)` | 85-89 | Decodes `[Chunk]` from a JSON URL and **replaces** `self.chunks`. |
| `save(to:)` | 79-82 | Serializes `chunks` to JSON (not a mutator). |

```swift
func addChunks(_ newChunks: [Chunk], deduplicate: Bool = true) {
    guard !newChunks.isEmpty else { return }
    if !deduplicate {
        chunks.append(contentsOf: newChunks)
        return
    }
    let existing = chunks
    let uniques = newChunks.filter { nc in
        !existing.contains { ec in ec.content == nc.content && ec.embedding == nc.embedding }
    }
    if !uniques.isEmpty {
        chunks.append(contentsOf: uniques)
    }
}
```

**Thread-safety of `shared`:** the `static let` initialization itself is safe (Swift
guarantees one-time init). But `chunks` is a bare `var` on a `class` with **no
synchronization** — only the internal `chunkCache` uses `cacheQueue`. Callers mutate
`VectorStore.shared.chunks` directly from arbitrary contexts (e.g. import hops to
`MainActor`, the executor reads it from a detached task). This is a latent data-race
risk but is **not** the cause of the empty store; the store is empty because no write
happens at all on the load path.

---

## Section 2 — Locate PersistenceStore and its RAGpack load path

`Shared/PersistenceStore.swift`. The function emitting the log line is
`loadRAGpackChunks()` — `PersistenceStore.swift:128-145`:

```swift
func loadRAGpackChunks() -> [String: [Chunk]] {
    guard fileManager.fileExists(atPath: ragpackChunksFileURL.path) else {
        NSLog("[PersistenceStore] ℹ️ No RAGpack Chunks file found (first launch)")
        return [:]
    }

    do {
        let data = try Data(contentsOf: ragpackChunksFileURL)
        let decoder = JSONDecoder()
        let chunks = try decoder.decode([String: [Chunk]].self, from: data)
        let sizeMB = Double(data.count) / (1024 * 1024)
        NSLog("[PersistenceStore] ✅ Loaded RAGpack Chunks: %.2f MB, %d packs", sizeMB, chunks.count)
        return chunks
    } catch {
        NSLog("[PersistenceStore] ❌ Failed to load RAGpack Chunks: %@", error.localizedDescription)
        return [:]
    }
}
```

- **Function producing the log line:** `PersistenceStore.loadRAGpackChunks()` — log at `PersistenceStore.swift:139`.
- **Type returned:** `[String: [Chunk]]` — a dictionary keyed by pack/doc name, each value a fully-decoded `[Chunk]` array (content **and** embeddings; the `%d packs` count is `chunks.count`, i.e. number of dictionary keys, = "1 packs" in the UAT log).
- **Where the loaded data is assigned:** the caller is `DocumentManager.loadRAGpackChunks()` — `DocumentManager.swift:106-108` — which stores the result into the `@Published var ragpackChunks` property:

```swift
func loadRAGpackChunks() {
    ragpackChunks = PersistenceStore.shared.loadRAGpackChunks()
}
```

`ragpackChunks` is declared at `DocumentManager.swift:45`:

```swift
/// POTENTIAL LARGE PAYLOAD: RAGpack chunks with embeddings (can be MBs per pack)
@Published var ragpackChunks: [String: [Chunk]] = [:]
```

This is the dead end: the persisted data lands in a `DocumentManager`-owned dictionary that the retrieval pipeline never reads.

---

## Section 3 — Find the connection (or absence) between PersistenceStore and VectorStore

Every `VectorStore.shared` call site in app/runtime code (tests excluded):

| File:line | Caller | Op | What is passed / returned |
|---|---|---|---|
| `Shared/DocumentManager.swift:55` | `embedder` computed prop | read | `.embeddingModel` (reuse embedder) |
| `Shared/DocumentManager.swift:113` | `deleteRAGpack(named:)` | **write** | `.chunks.removeAll { … }` (deletes pack's chunks) |
| `Shared/DocumentManager.swift:211` | `processRAGpackImport` | read | `.chunks.contains` (dedup check) |
| `Shared/DocumentManager.swift:216` | `processRAGpackImport` | **write** | `.chunks.append(contentsOf: uniqueChunks)` — **only lifecycle populate** |
| `Shared/ModelManager.swift:319` | debug print | read | `.chunks.count` |
| `Shared/ModelManager.swift:328` | retrieval helper | read | `LocalRetriever(store: VectorStore.shared)` |
| `Shared/ModelManager.swift:361` | debug print | read | `.chunks.count` |
| `Shared/Runtime/Executors/LocalExecutor.swift:81` | `execute` | read | `.chunks.count` (store-state log) |
| `Shared/Runtime/Executors/LocalExecutor.swift:95` | `execute` | read | `DeepSearch(store: VectorStore.shared, …)` |
| `Shared/Runtime/Executors/LocalExecutor.swift:98` | `execute` | read | `LocalRetriever(store: VectorStore.shared)` |
| `Shared/RAG/OnlineSGDReranker.swift:51` | reranker | read | `.embeddingModel.embed(...)` |
| `Shared/CLI/RagCLI.swift:170,181,213,331` | CLI demo | read | `.count` |
| `Shared/CLI/RagCLI.swift:179,222,339` | CLI demo | **write** | `.addTexts(docs)` (CLI demo corpus only) |

Mutating-method call sites outside the import path (`addTexts` / `addChunks` /
`load(from:)` / `reembedAll`) in app/runtime code: **none** except the CLI demo
(`RagCLI.swift`) and the test shims (`Apps/CLI/LlamaBridgeTest/TestRunnerShim.swift`,
`Apps/macOS/.../Tests/TestRunner.swift`). `VectorStore.shared.load(from:)` and
`reembedAll()` are **never** called from the production app.

Places that read `DocumentManager.ragpackChunks` and forward them to `VectorStore`:
grep for assignments/reads of `ragpackChunks` shows it is only read by
`saveRAGpackChunks()` (round-trips it back to disk) and written by
`loadRAGpackChunks()` (line 107) and the import path (line 217). **No code path reads
`ragpackChunks` and pushes it into `VectorStore.shared`.**

**Is there a call that populates `VectorStore.shared` from PersistenceStore's loaded
data? → No.** The persisted chunks are decoded into `DocumentManager.ragpackChunks`
and stop there. The retrieval store (`VectorStore.shared.chunks`) is only ever filled
by the *live import* append at `DocumentManager.swift:216`, which does not run on a
load-from-disk launch.

---

## Section 4 — Trace app startup to find all VectorStore.shared write calls

Startup sequence (macOS):

1. `@main struct NoesisNoemaApp` — `Shared/NoesisNoemaApp.swift:11-32`. `init()` builds a `HybridExecutionCoordinator`; `body` renders `DesktopRootView`. **No VectorStore access.**

```swift
@main
struct NoesisNoemaApp: App {
    private let executionCoordinator: ExecutionCoordinating
    init() { self.executionCoordinator = HybridExecutionCoordinator() }
    var body: some Scene {
        WindowGroup { DesktopRootView(executionCoordinator: executionCoordinator) }
    }
}
```

2. `DesktopRootView` owns the single shared `DocumentManager` — `Apps/macOS/NoesisNoema/Views/DesktopRootView.swift:36`:

```swift
@StateObject private var documentManager = DocumentManager()
```

3. `DocumentManager.init()` — `DocumentManager.swift:78-88` — runs migration, then `loadHistory()` / `loadRAGpackChunks()` / `loadQAHistory()`:

```swift
init() {
    self.llmragFiles = []
    PersistenceStore.shared.migrateFromUserDefaultsIfNeeded()
    loadHistory()
    loadRAGpackChunks()   // → fills ragpackChunks dict ONLY
    loadQAHistory()
}
```

A side effect of `init` is the first construction of `VectorStore.shared` (via the
`embedder` computed property at line 55 → the `static let shared`), which in turn
constructs `EmbeddingModel(name: "default-embedding")`. That initializes the store
**empty** (`chunks: [] `default).

**No write to `VectorStore.shared.chunks` happens during startup.** The only
lifecycle write sites are `DocumentManager.swift:216` (import append) and
`DocumentManager.swift:113` (delete removeAll) — neither is on the launch path. This
is the bug: the persisted corpus is never re-hydrated into the retrieval store.

---

## Section 5 — Trace RAGpack import path to find VectorStore write calls

Import entry: `DocumentManager.importDocument(file:)` — `DocumentManager.swift:122-149`
— validates the `.zip`, then `Task.detached { try await self.processRAGpackImport(...) }`.

`processRAGpackImport(fileURL:)` — `DocumentManager.swift:155-223` — unzips, reads +
validates via `RAGpackReader.readPack`, titles the chunks, dedups against the live
store, then writes:

```swift
let (chunks, _) = try RAGpackReader.readPack(at: tempDir, embedder: self.embedder)   // :193
// ... title chunks ...
let uniqueChunks = titledChunks.filter { chunk in                                    // :210
    !VectorStore.shared.chunks.contains(where: { $0.content == chunk.content && $0.embedding == chunk.embedding })
}

await MainActor.run {
    self.llmragFiles.append(ragFile)
    VectorStore.shared.chunks.append(contentsOf: uniqueChunks)   // :216  ← THE write
    self.ragpackChunks[docName] = uniqueChunks                   // :217  persistence cache
    self.uploadHistory.append(UploadHistory(...))
    self.saveHistory()
    self.saveRAGpackChunks()                                     // :220  → disk
    print("Imported RAGpack v1.2 document: \(docName) (\(uniqueChunks.count) unique chunks)")
}
```

- **Is `VectorStore.shared` written at the end of the import path?** Yes — `DocumentManager.swift:216`. So RAG *does* work within the same session right after a fresh import.
- **Where do chunks go otherwise?** On line 217 they are also stored in `ragpackChunks` and persisted to disk via `saveRAGpackChunks()` (line 220). On the **next launch** only the disk copy survives, and it is reloaded into `ragpackChunks` (Section 2/4) — never back into `VectorStore.shared`. So the in-memory store and the persisted store are kept in sync **only at import time, in one direction**, and the reverse (disk → VectorStore) hop is missing.

This explains the UAT exactly: the user's pack was imported in a prior session (so it
is on disk = "1 packs" loaded), but the current session never imported it, so
`VectorStore.shared.chunks.count == 0`.

---

## Section 6 — Understand EmbeddingModel initialization timing

`Shared/RAG/EmbeddingModel.swift`. `class EmbeddingModel` (`:17`), `init(name:)`
(`:42-63`), log line at `:50`:

```swift
init(name: String) {
    self.name = name
    if let path = EmbeddingModel.resolveEmbedderPath() {
        do {
            let ctx = try LlamaEmbeddingContext.load(modelPath: path)
            self.context = ctx
            self.dimension = ctx.dimension
            self.modelFingerprint = ctx.modelFingerprint
            print("[EmbeddingModel] Loaded embedder '\(name)' dim=\(ctx.dimension) fp=\(ctx.modelFingerprint.prefix(12))…")
        } catch { /* context = nil; dimension = 0 */ }
    } else { /* not found; context = nil */ }
}
```

- **Does EmbeddingModel init populate VectorStore? → No.** `init` only loads the GGUF context and records `dimension`/`modelFingerprint`. It has no reference to `VectorStore` and never touches `chunks`. It is purely the embedder, not the corpus.
- **Any lazy-load / on-demand populate on embedder readiness? → No.** There is no observer, no `didSet`, no readiness callback that would backfill `VectorStore.shared.chunks`. The embedder being ready has no effect on whether the store has data.

On the "loaded twice" observation: the first construction is the `VectorStore.shared`
`static let` (`VectorStore.swift:204`, `name: "default-embedding"`). The second
`[EmbeddingModel] Loaded embedder` near the executor's store-state log is a separate
`EmbeddingModel` construction at query time (the embedder is reconstructed rather than
reused). This is a redundant-load inefficiency but is **orthogonal** to the empty-store
bug — even a perfectly shared, ready embedder would still query an empty `chunks` array.
(See Section 8 for the exact second-load origin, which I could not pin down statically.)

---

## Section 7 — Fix proposal (describe, do not implement)

**Root cause:** the disk → in-memory re-hydration hop is missing. Persisted chunks are
loaded into `DocumentManager.ragpackChunks` but never pushed into
`VectorStore.shared.chunks`, which is the array the executor actually retrieves from.

**Minimal fix:** after `DocumentManager.loadRAGpackChunks()` populates `ragpackChunks`
at launch, flatten every pack's chunks and load them into the shared store. Concretely,
in `DocumentManager.init()` (or at the end of `loadRAGpackChunks()`), take
`ragpackChunks.values.flatMap { $0 }` and assign/append them to
`VectorStore.shared.chunks`. Because the persisted chunks already carry embeddings, use
a path that does **not** re-embed: either set `VectorStore.shared.chunks` directly, or
add a non-embedding bulk method (the existing `addChunks(_:deduplicate:)` works and
preserves embeddings; `addTexts` would wrongly re-embed and must be avoided).

- **Which function calls which method:** `DocumentManager` (launch path, right after
  `loadRAGpackChunks()`) → `VectorStore.shared.addChunks(allPersistedChunks, deduplicate: true)`
  (or a direct `.chunks =` assignment if the store is known-empty at that point).
- **Lifecycle point:** at **app startup**, once per launch, after the persisted dict is
  loaded. The import path (`:216`) already handles the live case and should be left as is.
- **Persistence vs in-memory sync:** they need to be reconciled on **every launch**
  (disk is the source of truth across sessions; the in-memory store is rebuilt from it),
  and additionally on import (already done). Today only the import direction exists.
- **Double-population risk:** real but bounded. If the startup populate runs and then
  the user imports the *same* pack in the same session, the import path's dedup
  (`:210-212`, content+embedding equality) already filters duplicates, so the store
  won't double up. The startup populate itself should also de-dup (or assign to a
  known-empty store) so re-entrant `DocumentManager` constructions — note the SwiftUI
  previews at `DesktopChatView.swift:352` etc. each call `DocumentManager()` — do not
  stack the same chunks. Using `addChunks(..., deduplicate: true)` covers both.
- **Caveat to verify before implementing:** confirm there is exactly one app-lifetime
  `DocumentManager` on the real launch path (`DesktopRootView.swift:36`); the many other
  `DocumentManager()` sites are `#Preview`/placeholder and would each trigger a populate.
  A guard (populate only when `VectorStore.shared.chunks.isEmpty`, or a one-shot flag)
  keeps previews and tests from interfering.

---

## Section 8 — Open questions

Items I could not resolve from static reading alone:

1. **Origin of the second `[EmbeddingModel] Loaded embedder` at query time.**
   `EmbeddingModel.swift:42-63` is the only constructor with that log, but statically I
   could not determine which call site reconstructs an embedder during
   `LocalExecutor.execute` (`Shared/Runtime/Executors/LocalExecutor.swift:70-149`) — it
   may be inside `LocalRetriever`/`DeepSearch` or the v1.2 reader. A runtime breakpoint
   on `EmbeddingModel.init` (or `EmbeddingModel.swift:50`) would name the exact caller.
   Relevant only for the redundant-load inefficiency, not the P0 empty-store bug.

2. **Whether `ModelManager` ever runs a populate I did not see.**
   `ModelManager.swift:319/328/361` are all reads in this build, but `ModelManager` is
   large; I read only the `VectorStore.shared` lines. A full read of
   `ModelManager.swift` around those sites would confirm no populate hook exists there.

3. **Chunk embedding dimension on the persisted path.** The persisted chunks are decoded
   with their stored embeddings (`PersistenceStore.swift:137`). I assume they are 768-dim
   (matching the current `nomic-embed-text-v1.5` embedder, `EmbeddingModel.swift:22`). If
   an older pack was persisted with a different dimension, `VectorStore.findRelevant`
   (`VectorStore.swift:96-120`) silently skips mismatched-dim chunks — worth a runtime
   check once the populate fix lands, but it does not affect the current count=0 symptom.
