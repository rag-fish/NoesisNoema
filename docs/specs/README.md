# Specs

Local mirrors of runtime-relevant specs whose canonical copies live in `rag-fish/RAGfish`. See each file's header for the canonical path.

## spec-runtime-v0.9-handover.md

Governance rule → runtime component mapping (Noema ADR-0003):

| Governance rule | Runtime component |
|---|---|
| G1 (no ungrounded generation) | `ProvenanceGate` |
| G5 (budget enforcement pre-inference) | `BudgetEnforcer` |
| G6 (audit completeness) | `AuditEmitter` |
| export | `EvidenceExporter` |

### Acceptance criteria (v0.9)
1. Conformance vectors pass (Swift emitter == Python emitter hashes).
2. A grounded answer displays citations; an ungrounded answer displays `model-only`; no third state exists.
3. `noema-evidence verify` (Python, pipeline side) validates a package exported from the device.
4. Zero added latency measurable on the query path beyond hash-append (<5 ms budget).
5. Min-spec device n_ctx validation completed and recorded as an audit event.
