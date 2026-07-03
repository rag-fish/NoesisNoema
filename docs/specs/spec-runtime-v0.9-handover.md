> Canonical copy: `rag-fish/RAGfish` at `docs/noema/specs/spec-runtime-v0.9-handover.md`. This is a local mirror for implementation sessions in this repo; the RAGfish copy is authoritative.

# Spec: Runtime Enforcement v0.9 (NoesisNoema, pure Swift) — Implementation Handover

**Status:** Specification frozen in v0.8; implementation deferred to v0.9.
**Hard constraints:** pure Swift only (no Python, no subprocess, no PythonKit). CryptoKit is the only crypto dependency. llama.cpp xcframeworks remain vendored out-of-git.

## Components

### 1. `PolicyManifest` (loader)
- Parses `noema-policy.yaml` bundled or imported; pins by sha256 recorded at import.
- Swift has no first-party YAML parser: either vendor Yams (SPM, pure Swift — allowed) or ship the policy as JSON alongside YAML (pipeline converts; JSON is authoritative on device). **Decision left to implementer; JSON sidecar is the lower-risk path.**
- Exposes typed accessors: `g1MinChunksCited`, `g5NCtx`, `g5TrimStrategy`, `auditRequired`.

### 2. `ProvenanceGate` (G1)
- Input: retrieval result set + generation request.
- If cited chunks ≥ `min_chunks_cited` → grounded path; answer object carries `[ChunkCitation]` (chunk_id, score, pack_id).
- Else → generation proceeds with `answerKind = .modelOnly`; UI renders the `model-only` label prominently. G1 labels, never silently blocks (v0.9 scope).
- Ungoverned packs (manifest without `governance` block) force `.modelOnly` labeling regardless of scores.

### 3. `BudgetEnforcer` (G5)
- Wraps the existing token-budget manager (v0.4). No behavioral change; parameters (`n_ctx`, trim strategy) now sourced from `PolicyManifest` instead of constants.
- Validated baseline: n_ctx 4096 non-constraining on iPhone 17 Pro Max. Open item inherited from v0.4: min-spec device validation (HIGH) — becomes a v0.9 acceptance criterion.

### 4. `AuditEmitter` (G6, runtime side)
- Append-only JSONL in app container (`Application Support/audit/audit-device.jsonl`).
- Schema and hash chain identical to spec-audit-pipeline.md §1–2. JCS canonicalization in Swift MUST pass `audit/conformance/vectors.json` byte-for-byte — this is the first test to write.
- Numbers-as-strings rule applies (scores emitted as `"0.87"`).
- SHA-256 + Ed25519 via CryptoKit (`SHA256`, `Curve25519.Signing`).
- Emits `query.retrieve` and `query.generate` with the G2 triplet `(embedder_id, model_id, manifest_sha256)`.

### 5. `EvidenceExporter`
- Explicit user action only (share sheet). Builds the tar.gz per spec-audit-pipeline.md §3.
- Default content-free; `--include-queries` equivalent is a settings toggle with a confirmation dialog, and toggling it emits an audit event.
- Signing key: generated on device, stored in Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`); public key displayable/exportable for out-of-band trust anchoring.

## Acceptance criteria (v0.9)
1. Conformance vectors pass (Swift emitter == Python emitter hashes).
2. A grounded answer displays citations; an ungrounded answer displays `model-only`; no third state exists.
3. `noema-evidence verify` (Python, pipeline side) validates a package exported from the device.
4. Zero added latency measurable on the query path beyond hash-append (<5 ms budget).
5. Min-spec device n_ctx validation completed and recorded as an audit event.

## Out of scope for v0.9
- G1 blocking mode (labeling only).
- Merkle proofs, platform attestation (App Attest).
- Any cloud component.
