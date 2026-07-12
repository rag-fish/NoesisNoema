# Claude Code Handover — xcframework embedding-parity UAT (NoesisNoema)

Repo: rag-fish/NoesisNoema.
Guard (FIRST): `git remote get-url origin` must contain `rag-fish/NoesisNoema`; else STOP.
Branch: `uat/xcframework-nomic-parity`.

Purpose: verify that the locally built llama.cpp xcframework produces embedding
geometry consistent with the pipeline's G3 gate run (llama-server, commit e5b5ec178),
i.e. G2 version-pinning validated at the runtime layer.

Parameters (Taka fills in):
- `PACK_DIR=<path to packs/g3_demo_nomic in the pipeline repo>` (untracked pack from Session D2)
- `GGUF=~/Downloads/nomic-embed-text-v1.5.Q5_K_M.gguf`

## Preconditions (STOP + report on failure)
1. Locate the vendored xcframework (FRAMEWORK_SEARCH_PATHS / build script output).
   Determine the llama.cpp source commit it was built from
   (`git -C ~/CLionProjects/llama.cpp rev-parse HEAD`, or the build script's record).
   - If commit == e5b5ec178 → full parity expectations apply.
   - If different → do NOT stop, but mark the entire UAT report ADVISORY and
     state both commits prominently. Recommend rebuild-at-pinned-commit in the report.
2. `sha256sum $GGUF` must equal the value recorded in pipeline PR #32's G2 block; mismatch → STOP.
3. Xcode toolchain builds the macOS app target against the xcframework (build sanity).

## UAT steps
A. **Harness (isolated, no app-source changes):** create a minimal SPM executable
   under `uat/parity-harness/` that links the xcframework by local path and exposes:
   embed(text, prefix) -> [Float]. Do NOT modify app sources or the app .xcodeproj.
   Pure Swift only (no Python, no subprocess to python).
B. **Embedding parity (5 fixed inputs):** 3 gold-set queries (q001, q027, q035 —
   include the near-duplicate discriminators) with "search_query: " prefix, and
   2 chunk texts from $PACK_DIR/chunks.json with "search_document: " prefix.
   Reference vectors: start `llama-server --embedding -m $GGUF` (same binary/commit
   as the gate run), fetch the same 5 embeddings over HTTP, shut it down after.
   Metric: cosine similarity per pair. Expectation at same commit: >= 0.999
   (report exact values; do not round to 1.0).
C. **Retrieval parity:** using the harness embeddings + $PACK_DIR (apply
   mean-centering exactly as the manifest dictates), compute top-5 chunk ids for
   the 3 queries; compare with the gate run's per-query top-5 from PR #32's report.
   Report overlap per query (n/5).
D. **Report:** `docs/uat/2026-07-12-xcframework-nomic-parity.md` (this repo's
   .gitignore blanket-excludes *.md — use `git add -f`, precedent in PR #126).
   Must contain a G2 pinning block: xcframework llama.cpp commit, gate-run commit
   (e5b5ec178), GGUF sha256, pack manifest sha256, Xcode/macOS versions;
   parity tables from B/C; NO pass/fail verdict — the verdict line is left as
   an empty "Human sign-off:" field for Taka.

## Prohibitions
- No app source or .xcodeproj changes. No xcframework binaries committed.
- No merge; open PR `uat: xcframework nomic embedding parity vs G3 gate run`.
- Archive this prompt per repo convention.

## Human double-check checklist (for Taka, on the PR)
- [ ] llama.cpp commit: xcframework == e5b5ec178 (gate run)? If not, is ADVISORY marked?
- [ ] GGUF sha256 matches PR #32's G2 block?
- [ ] Cosine >= 0.999 for all 5 pairs (actual values listed, not rounded)?
- [ ] Top-5 overlap 5/5 for all 3 queries, with mean-centering applied per manifest?
Sign-off = fill "Human sign-off: taka, <date>" in the report, then merge.

## Session note (added post-run)

`PACK_DIR` was not filled in by the invoking user; it was supplied
interactively during the session as
`/Users/raskolnikoff/PycharmProjects/noesisnoema-pipeline/packs/g3_demo_nomic`.
Step C's literal target ("gate run's per-query top-5 from PR #32's report")
was not recoverable — `report.json`/`report-detail.json` was never committed
(PR #32 states pack/report artifacts are untracked) and is not present on
disk. Reconstructed the reference side from the pack's own `embeddings.npy`
(hash-verified against the manifest) instead; see the deviation note in the
UAT report.
