# Retrieval Quality Root-Cause Audit

**Date:** 2026-06-16
**Scope:** READ-ONLY. No retrieval logic was changed. This document records findings only.
**Symptom under investigation:** Poor retrieval quality — (a) correct chunks don't rank
high, and (b) relevant chunks aren't retrieved at all.
**Prime hypothesis:** `nomic-embed-text-v1.5` requires asymmetric task prefixes
(`search_query: ` for queries, `search_document: ` for documents). Missing or
asymmetric prefixes are the prime suspect.

---

## TL;DR verdict

| Question | Verdict | Evidence |
|---|---|---|
| Query-side `search_query: ` prefix present? | **YES** | `EmbeddingModel.swift:24,78` |
| Document-side `search_document: ` prefix used at pack build? | **UNKNOWN from the app — and likely NOT applied / unverifiable** | No prefix field in the manifest schema; docs are embedded by the external pipeline, not this app. See §2. |
| Query vector L2-normalized before similarity? | **YES** | `LlamaEmbeddingContext.swift:176–183` |
| Embedder confirmed as nomic, dim 768? | **YES** | `EmbeddingModel.swift:22`; dim 768 validated against pack at import (`RAGpackManifest.swift:129`) |

**Root-cause assessment.** The query path is correctly and unconditionally prefixed
with `search_query: `. The document path is **precomputed by an external pipeline**
(`noesisnoema-pipeline`) and imported verbatim; **this repo never embeds documents in
the live import path**, and the RAGpack manifest schema **has no field that records
whether a document-side prefix was applied**. Therefore the single most likely
asymmetry — query embedded with `search_query: ` while documents were embedded with
*no* prefix (or a different one) — **cannot be confirmed or ruled out from this
codebase alone**. It must be verified against the pipeline that built the packs. This
is the prime suspect and the top action item.

---

## 1. Query embedding path

### Where the query is embedded at search time
The query string is embedded through `EmbeddingModel.embed(text:)`. Call sites in the
live retrieval path:

- `LocalRetriever.swift:77` — final MMR rerank: `let qEmb = embedder.embed(text: query)`
- `VectorStore.swift:148` — embedding-stage candidate retrieval: `let queryEmbedding = embeddingModel.embed(text: query)`
- `BanditRetriever.swift:30` — min-score filter: `let q = store.embeddingModel.embed(text: query)`
- `DeepSearch.swift:75` — multi-round deep search.

All of them funnel into the same method.

### Is `search_query: ` prepended before embedding? — YES
`Shared/RAG/EmbeddingModel.swift`:

```swift
// line 24
private static let taskPrefix = "search_query: "

// lines 77–78
func embed(text: String) -> [Float] {
    let prefixed = EmbeddingModel.taskPrefix + text
```

The raw query is **never** sent to the embedder; the exact string handed to llama.cpp
is `"search_query: " + query`. The class header documents the intent explicitly
(`EmbeddingModel.swift:14–16`):

```swift
/// nomic-embed-text-v1.5 requires task prefixes; PR-A only has query-side callers
/// so it always applies `"search_query: "`. PR-B introduces `"search_document: "`
/// for pack-side ingestion in the v1.2 RAGpackReader.
```

> **Latent hazard (not on the live import path).** Because the prefix is applied
> *inside* `embed(text:)` unconditionally, **any** caller that embeds *document* text
> through this method gets `search_query: ` wrongly. Two such callers exist —
> `VectorStore.addTexts()` (`VectorStore.swift:44`) and `VectorStore.reembedAll()`
> (`VectorStore.swift:74`). These are **not** used by the v1.2 RAGpack import path
> (which uses precomputed vectors — see §2), but if any code path ever embeds
> documents in-app, they would be embedded with the *query* prefix. Worth noting for
> follow-up, but not the live-path root cause.

### Embedder confirmed as nomic GGUF, dim 768 — YES
`EmbeddingModel.swift:22–23`:

```swift
static let embedderResourceName = "nomic-embed-text-v1.5.Q5_K_M"
static let embedderResourceExt = "gguf"
```

Dimension is read dynamically from the loaded model
(`LlamaEmbeddingContext.swift:96` `let n_embd = Int(llama_model_n_embd(model))`) and
is **768** for this model, confirmed by the import validator and manifest fixtures
(`RAGpackManifest.swift:153`, `"embedding_dimension": 768`).

---

## 2. Document embedding origin

### The app does NOT embed documents — confirmed
RAGpacks are imported by `RAGpackReader.readPack(at:embedder:)`. Documents arrive as a
**precomputed** embeddings matrix; the reader never calls the embedder on document
text. `Shared/RAG/RAGpackReader.swift` header (lines 3–15) and body:

```swift
//   v1.2 two-file split (ADR-0011 §5): the pipeline writes chunks.json as a FLAT
//   ARRAY OF CHUNK TEXT ... aligned with the embeddings.npy row order. We decode
//   chunks.json as `[String]`, then assemble `[Chunk]` in memory by joining each
//   text with `embeddings[i]` and `citations[i]`. The app is a CONSUMER of v1.2
//   packs; it never emits the object shape.
```

The embeddings are read from disk (`RAGpackReader.swift:55–78`), reshaped, and joined
by index to chunk text — never recomputed:

```swift
let embeddingsURL = unzippedDir.appendingPathComponent(manifest.files.embeddings)
...
(shape, flat) = try NumpyReader.readFloat32(from: embeddingsURL)
...
embeddings.append(Array(flat[start..<(start + dim)]))
```

> **Note on file format.** The original task brief referred to `embeddings.csv`. The
> current v1.2 reader consumes **`embeddings.npy`** (`manifest.files.embeddings`,
> read via `NumpyReader`). The header explicitly calls the v0.x CSV path an
> *anti-goal* (`RAGpackReader.swift:7`). `embeddings.csv` survives only as an
> informational entry in some manifest `files.metadata` blocks
> (`RAGpackManifest.swift:155`). Either way: **the app reads precomputed vectors; it
> does not embed documents.**

### What prefix were the documents embedded with? — UNKNOWN / unverifiable from this repo
This is the crux of the audit, and the answer is **we cannot tell from the app**:

1. **No prefix field exists in the manifest schema.** `RAGpackManifest.EmbedderInfo`
   (`RAGpackManifest.swift:54–72`) records `embedding_model`, `embedding_dimension`,
   `model_hash`, `dtype`, `pooling`, `l2_normalized`, `runtime` — **and nothing about
   a task prefix or instruction.** A pack built with `search_document: ` and one built
   with no prefix are **indistinguishable** to the importer; both validate identically.

2. **`search_document` appears nowhere as executable code.** A repo-wide search finds
   exactly two hits, both in the same comment describing *future* PR-B work:

   ```
   Shared/RAG/EmbeddingModel.swift:15  ... PR-B introduces `"search_document: "`
   Shared/RAG/EmbeddingModel.swift:24  private static let taskPrefix = "search_query: "
   ```

   There is no `search_document: ` constant, no document-prefixing code, and no
   pipeline script in this repo.

3. **Documents are built by an external pipeline.** Comments reference
   `noesisnoema-pipeline` as the producer of packs and citations
   (`RAGpackManifest.swift:4–6`, `RAGpackReader.swift:204–205`). The actual
   document-embedding code — and therefore the actual document-side prefix — lives in
   that repo, not here. **Verifying the document prefix requires inspecting that
   pipeline or the raw vectors in an existing pack** (e.g. the Spinoza Ethica pack,
   `pack-9edb42ffa01d5da2c388d03f42562c70`, referenced at `RAGpackManifest.swift:150`).

**Interpretation for the symptom.** nomic-embed-text-v1.5 is *designed* for asymmetric
prefixes: a `search_query: ` query is meant to be matched against `search_document: `
documents. The query side does this correctly. If the packs were built **without**
`search_document: ` (or with a different prefix), the query and document vectors live
in mismatched regions of the embedding space — exactly producing "correct chunks rank
low" and "relevant chunks not retrieved." Given that nothing in this repo applies a
document prefix and the schema doesn't even record one, **a missing document-side
prefix is the leading hypothesis and the highest-priority thing to verify upstream.**

### Document vector dimension / model — confirmed consistent
Import is gated on a strict fingerprint + dimension check
(`RAGpackManifest.swift:116–138`): the pack must be `dim == 768`, `dtype float32`,
`pooling mean`, `l2_normalized true`, and the GGUF `model_hash` must match the app's
loaded embedder fingerprint, or the import is rejected
(`RAGpackImportError.embedderFingerprintMismatch`). So document vectors are guaranteed
to come from the *same nomic model* as the query embedder — the asymmetry risk is
about the **prefix**, not the model.

---

## 3. Embedding normalization

### Query vector L2-normalized? — YES
Normalization happens at embed time inside the actor, so every returned vector
(including the query) is unit-length. `Shared/Llama/LlamaEmbeddingContext.swift:176–183`:

```swift
// L2-normalize.
var sumSq: Float = 0
for v in vec { sumSq += v * v }
let norm = sumSq.squareRoot()
guard norm > 0, norm.isFinite else { throw EmbeddingError.zeroNorm }
for i in 0..<dimension { vec[i] /= norm }
return vec
```

### Document vectors assumed normalized? — YES, and enforced
Packs must declare `l2_normalized: true` or import fails
(`RAGpackManifest.swift:126–128`, `RAGpackImportError.embedderNotL2Normalized`).

### Does the similarity function depend on it? — No (defensive full cosine)
Both similarity implementations compute a **full cosine** (dividing by both norms), so
they are correct whether or not inputs are unit-length:

- `VectorStore.cosineSimilarity` (`VectorStore.swift:122–139`)
- `MMR.cosine` (`MMR.swift:51–59`)
- `BanditRetriever.cosine` (`BanditRetriever.swift:42–50`)

```swift
let denom = (sqrtf(max(na, 1e-9)) * sqrtf(max(nb, 1e-9)))
if denom == 0 { return 0 }
return dot / denom
```

**Conclusion:** normalization is correct and not a contributor to the symptom.

---

## 4. Retrieval pipeline shape

End-to-end flow and where each step lives:

```
query
  └─ BanditRetriever.retrieve              BanditRetriever.swift:23
       ├─ ParamBandit.chooseParams         ParamBandit.swift  (Thompson sampling → topK / mmrLambda / minScore)
       └─ LocalRetriever.retrieve(k,λ)      LocalRetriever.swift:33
            ├─ QueryIterator.variants        LocalRetriever.swift:51  (query expansion, on by default)
            ├─ BM25 candidates               LocalRetriever.swift:66  (bm25TopK, stageCandidates=12/strategy)
            ├─ Embedding candidates          LocalRetriever.swift:70  → VectorStore.retrieveChunks
            │     └─ embed query + cosine    VectorStore.swift:146 / findRelevant:96 / cosineSimilarity:122
            ├─ dedupe by content             LocalRetriever.swift:63–71
            ├─ embed query (search_query:)   LocalRetriever.swift:77
            └─ MMR.rerank → top-K            MMR.swift:18  (relevance vs. diversity, λ)
       └─ min-score filter                   BanditRetriever.swift:28–37  (cosine(query, chunk) ≥ minScore)
```

It is a **hybrid BM25 + dense** retriever with query iteration, MMR diversity rerank,
and a post-hoc min-score cutoff selected per-query by a Thompson-sampling bandit.

### Current default parameters

| Param | Default(s) | Where |
|---|---|---|
| `topK` | 5 (`LocalRetriever.Config`); bandit arms 4 / 5 / 6 / 8 | `LocalRetriever.swift:17`; `ParamBandit.swift:49–52` |
| `mmrLambda` | 0.7 (`LocalRetriever`, `MMR`, `DeepSearch`); bandit arms 0.7 / 0.9 / 0.7 / 0.5 | `LocalRetriever.swift:16`; `MMR.swift:18`; `ParamBandit.swift:49–52` |
| `minScore` | bandit arms 0.20 / 0.10 / 0.15 / 0.15 (LocalRetriever itself has no min-score) | `ParamBandit.swift:49–52`; filter at `BanditRetriever.swift:28–37` |
| `stageCandidates` | 12 per strategy | `LocalRetriever.swift:15` |
| `bm25_k1 / bm25_b` | 1.5 / 0.75 | `LocalRetriever.swift:13–14` |

Bandit arms (`ParamBandit.swift:49–52`):

```swift
Arm(id: "k4_l0.7_s0.20", params: .init(topK: 4, mmrLambda: 0.7, minScore: 0.20)),
Arm(id: "k5_l0.9_s0.10", params: .init(topK: 5, mmrLambda: 0.9, minScore: 0.10)),
Arm(id: "k6_l0.7_s0.15", params: .init(topK: 6, mmrLambda: 0.7, minScore: 0.15)),
Arm(id: "k8_l0.5_s0.15", params: .init(topK: 8, mmrLambda: 0.5, minScore: 0.15))
```

> **Secondary observation (not the root cause).** The `minScore` cutoffs (0.10–0.20)
> are interpreted as raw cosine on nomic vectors. nomic cosine scores between a
> correctly-prefixed query and document are typically high (~0.5–0.8); if the
> query/document prefixes are *mismatched*, genuine matches can fall *below* these
> thresholds and be filtered out entirely — which would directly cause "relevant
> chunks aren't retrieved at all." This amplifies the §2 prefix hypothesis rather
> than being an independent cause. The dynamic `topK` shrink for short queries
> (`LocalRetriever.dynamicTopK`, `swift:83–90`, clamps to 2 for queries < 20 chars)
> is also worth a look, but again secondary.

---

## 5. Model consistency

| Role | README says | Actually wired in code | Verdict |
|---|---|---|---|
| Generator (LLM) | `Jan-v1-4B-Q4_K_M.gguf` (`README.md:109`) | `Llama-3.2-3B-Instruct-Q4_K_M.gguf` | README is **stale**; code uses Llama-3.2-3B |
| Embedder | — | `nomic-embed-text-v1.5.Q5_K_M.gguf`, dim 768 | matches handover |

Generator evidence:
- `LLMModel.swift:66` — `let fileName = modelFile.isEmpty ? "Llama-3.2-3B-Instruct-Q4_K_M.gguf" : modelFile`
- `LlamaState.swift:47` — `let primaryFile = "llama-3.2-3b-instruct-q4_k_m.gguf"`
- `NoesisCompletionPipeline.swift:210` — `/// The active generator is Llama-3.2-3B-Instruct, which expects the Llama-3` chat template (matches recent commits #108–#111 that switched the prompt to the Llama-3 template).

Embedder evidence: `EmbeddingModel.swift:22`, validated to dim 768 at import
(`RAGpackManifest.swift:129`).

**Conclusion:** The handover description (llama-3.2-3b generator + nomic-embed-text-v1.5
embedder, dim 768) is **accurate**. The README's "Jan-v1-4B" is outdated documentation
and is **not** a retrieval-quality factor — but it should be corrected to avoid
confusion.

---

## Recommended next steps (out of scope for this PR — no logic changed here)

1. **Verify the document-side prefix upstream (highest priority).** Inspect
   `noesisnoema-pipeline` (or dump raw vectors from an existing pack such as the
   Spinoza Ethica pack) to confirm whether documents were embedded with
   `search_document: `, no prefix, or something else. This is the prime suspect.
2. **Record the prefix in the manifest.** Add an embedder field (e.g.
   `query_prefix` / `document_prefix` or a single `task_prefix_scheme`) to
   `RAGpackManifest.EmbedderInfo` so the asymmetry is *verifiable at import* and packs
   built with the wrong scheme are rejected like a fingerprint mismatch — turning a
   silent quality bug into a loud error.
3. **Once #1 is known**, align the app: keep `search_query: ` on the query side iff
   documents carry `search_document: `; otherwise fix the side that's wrong. (This is
   the PR-B work the `EmbeddingModel.swift:14–16` comment anticipates.)
4. **Guard the in-app document embedders** (`VectorStore.addTexts` / `reembedAll`) so
   they cannot apply the query prefix to document text if they're ever used.
5. **Fix the stale README** generator name (`Jan-v1-4B` → `Llama-3.2-3B-Instruct`).

---

## Files inspected (read-only)

`Shared/RAG/EmbeddingModel.swift`, `Shared/RAG/LocalRetriever.swift`,
`Shared/RAG/VectorStore.swift`, `Shared/RAG/MMR.swift`,
`Shared/RAG/RAGpackReader.swift`, `Shared/RAG/RAGpackManifest.swift`,
`Shared/RAG/BanditRetriever.swift`, `Shared/RAG/ParamBandit.swift`,
`Shared/RAG/DeepSearch.swift`, `Shared/Llama/LlamaEmbeddingContext.swift`,
`Shared/LLMModel.swift`, `Shared/Llama/LlamaState.swift`,
`Shared/Llama/NoesisCompletionPipeline.swift`, `README.md`.
