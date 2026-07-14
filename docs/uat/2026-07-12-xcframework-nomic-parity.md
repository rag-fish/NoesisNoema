# UAT: xcframework nomic-embed-text-v1.5 embedding parity vs G3 gate run

Compares embeddings produced by the vendored `llama.xcframework`
(`NoesisNoema/Frameworks/xcframeworks/llama.xcframework`) against the
llama-server reference run recorded in pipeline PR #32
(`rag-fish/noesisnoema-pipeline#32`, "g3_demo goldset.jsonl + first G3
calibration run"), to check whether G2 version-pinning holds at the runtime
(app-embedded) layer, not just the pipeline layer.

## G2 pinning block

| field | value |
|---|---|
| gate-run llama.cpp commit (PR #32) | `e5b5ec178d145a762ab847d22b16bb490fb6af4d` (2026-07-10) |
| xcframework llama.cpp commit attribution | `e5b5ec178d145a762ab847d22b16bb490fb6af4d` — **not cryptographically embedded in the binary** (no `LLAMA_BUILD_COMMIT`/build-info string found via `strings` on the compiled `llama.framework/llama`). Attributed by: (a) the only local llama.cpp checkout that is currently at this commit is `~/CLionProjects/llama.cpp`, with the exact same uncommitted CMake-only working-tree diff (`CMakeLists.txt`, `ggml-hexagon/htp/CMakeLists.txt`, `ggml-hip/CMakeLists.txt`) that PR #32 documents; (b) the xcframework binary's mtime (2026-07-10 11:29 local) matches that commit's date and postdates the repo's only other vendored checkout (`.build/llama.cpp`, commit `cb623de3`, dated 2025-11-17 — stale, does not match); (c) the `llama-server` binary used for the reference run in this UAT (built from the same `~/CLionProjects/llama.cpp` checkout) self-reports `version: 9936 (e5b5ec178)`. No build script or commit log in this repo records the xcframework build directly. **Treat as strong circumstantial attribution, not a hard-pinned build record.** |
| GGUF sha256 | `0c7930f6c4f6f29b7da5046e3a2c0832aa3f602db3de5760a95f0582dbd3d6e6` — verified equal to local `~/Downloads/nomic-embed-text-v1.5.Q5_K_M.gguf` and to PR #32's G2 block. |
| pack manifest sha256 | `ecbd4b55ab9f7db205d6d12c08242be5fe5691a74894bbf2a8100a2461cec59c` — verified equal to local `packs/g3_demo_nomic/manifest.json` (pipeline repo, untracked pack from Session D2) and to PR #32's G2 block. |
| pack embeddings.npy sha256 | `622322d27eeedc8356879cce6641c67962f3260b2be153ec8f6d9a8304443db3` — verified equal to the `embeddings_sha256` recorded inside that same manifest (i.e. the on-disk `embeddings.npy`/`embeddings.csv` used for step C below is exactly the artifact the manifest — and by extension PR #32's gate run — declares itself to contain). |
| pack chunks.json sha256 | `dbe01a38c551bc754318d975c7ec3aa09bab87e66a028e32330d7e0dc7b4c9f9` — verified equal to the manifest's `chunks_sha256`. |
| Xcode | 26.6 (17F113) |
| macOS | 26.5.2 (25F84) |

### Deviation from handover: reconstructed retrieval reference

The handover asked to compare retrieval parity against "the gate run's
per-query top-5 from PR #32's report" (`report.json`/`report-detail.json`).
That file was never committed (PR #32 states pack/report artifacts are
untracked) and is not present on disk in the pipeline repo checkout used for
this UAT. In its place, step C below reconstructs the reference side from
the pack's own `embeddings.npy` (hash-verified against the manifest, see
table above) plus a fresh query embedding from the pinned-commit
`llama-server`, and runs both through the pack's declared
`RetrievalHarness` geometry (`retrieval/harness.py`: L2-normalize → mean-center
by corpus centroid → L2-normalize). This is the same document-side data the
gate run scored against (verified by hash), so it should be equivalent to
diffing against the original report — but it is a reconstruction, not a
diff against the literal stored artifact.

## Harness

`uat/parity-harness/`: pure-Swift SPM executable, `Package.swift` with a
`.binaryTarget` pointing at the vendored xcframework by local path plus an
executable target that links it. `Sources/parity-harness/main.swift` loads
the GGUF via the raw `llama.h` C API (`llama_model_load_from_file` →
`llama_init_from_model` with `embeddings = true`, default/unspecified
pooling type so it defers to the model's own GGUF-declared pooling, same as
a `llama-server` run with no `--pooling` override) and exposes
`embed(text:prefix:) -> [Float]`. Tokenization mirrors llama.cpp's own
`examples/embedding/embedding.cpp` (`add_special=true, parse_special=true`,
every token position marked for output so the model's internal mean-pooling
sees the full sequence). No app source or `.xcodeproj` changes; no
subprocess to Python.

## Step B — embedding parity (5 fixed inputs)

Reference vectors from `~/CLionProjects/llama.cpp/build-macos/bin/llama-server
--embedding -m nomic-embed-text-v1.5.Q5_K_M.gguf` (`version: 9936
(e5b5ec178)`), `POST /embedding`, same prefixing convention
(`search_query: ` / `search_document: `) as `retrieval/llama_server_embedder.py`
and `embedder/llamacpp_embedder.py`. Server started fresh for this run and
shut down immediately after.

| id | text | cosine(harness, reference) |
|---|---|---|
| q001 | "What is human bondage?" | 0.9999999999999996 |
| q027 | "How do freedom and bondage relate to acting from one's own nature versus being overpowered by passions?" | 0.9999999999999994 |
| q035 | "How does virtue connect to the definition of a free thing acting from necessity of its own nature?" | 0.9999999999999994 |
| chunk 0 | "Human freedom consists in acting from the necessity of one's own nature, not in escaping causation." | 0.9999999999999993 |
| chunk 18 | "A thing is called free which exists from the necessity of its own nature alone." | 0.9999999999999994 |

q027 and q035 are the near-duplicate discriminators from the g3_demo
goldset review (`goldsets/g3_demo/goldset-review.md`, rows 27/28/35): chunk
0 and chunk 18 are near-duplicate "freedom" definitions the goldset was
specifically designed to distinguish between.

All 5 pairs clear the ≥0.999 expectation by a wide margin (values shown
exact, not rounded — the residual ~4×10⁻¹⁶ is float64 accumulation noise,
not a geometry mismatch).

## Step C — retrieval parity (top-5 per query)

`packs/g3_demo_nomic` (20 chunks), `RetrievalHarness` geometry applied
identically to both sides (`normalization: mean_center` per manifest).

| query | harness top-5 (chunk ids, ranked) | reference top-5 (chunk ids, ranked) | overlap | goldset relevant ids |
|---|---|---|---|---|
| q001 | 1, 0, 17, 9, 5 | 1, 0, 17, 9, 5 | 5/5 | [1] |
| q027 | 1, 0, 16, 10, 18 | 1, 0, 16, 10, 18 | 5/5 | [0, 1] |
| q035 | 10, 18, 0, 16, 2 | 10, 18, 0, 16, 2 | 5/5 | [10, 18] |

Harness and reference produce byte-identical *ranked* top-5 lists (not just
same-set) for all 3 queries, and each query's goldset-relevant id(s) land at
or near the top, consistent with PR #32's reported Recall@5 = 1.0000 on this
pack.

## Human sign-off

Human sign-off: _(pending — Taka to fill in: `taka, <date>`)_
