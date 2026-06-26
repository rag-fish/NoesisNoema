# Audit: NoesisNoema Agent-Routing Inventory

**Date:** 2026-06-26
**Branch:** `audit/noesisnoema-agent-routing-inventory`
**Status:** Read-only — no source changes
**Closes:** rag-fish/NoesisNoema#119

---

## 1. Repository Structure

### Major modules

| Path | Role |
|------|------|
| `Shared/Routing/` | Deterministic routing layer (Router, NoemaQuestion, RoutingDecision, etc.) |
| `Shared/Runtime/Execution/` | Hybrid execution orchestrator (HybridExecutionCoordinator) |
| `Shared/Runtime/Executors/` | Local and cloud executor implementations |
| `Shared/Runtime/Networking/` | HTTP client for noema-agent |
| `Shared/Runtime/Tracing/` | Audit-log pipeline (ExecutionTrace, TraceCollector, FileTraceSink) |
| `Shared/Runtime/Policy/` | PolicyResult types |
| `Shared/Policy/` | PolicyEngine, PolicyRule, ConstraintStore, ConditionEvaluators |
| `Shared/Execution/` | Legacy ExecutionCoordinator (slated for R4 removal) |
| `Shared/Constraints/` | ConstraintRuntime, ExecutionConstraint, ConstraintViolation |
| `Shared/RAG/` | VectorStore, LocalRetriever, DeepSearch, EmbeddingModel, RAGpackReader |
| `Shared/Llama/` | LlamaInferenceEngine, LlamaEmbeddingContext, NoesisCompletionPipeline |
| `Shared/UI/` | MinimalClientView (EPIC1 X-1 interface) |
| `Shared/Utils/` | ConnectivityGuard, SystemLog |
| `Shared/Feedback/` | FeedbackStore, RewardBus |
| `Apps/macOS/NoesisNoema/` | macOS target (Views, ModelRegistry, Tests) |
| `Apps/iOS/NoesisNoemaMobile/` | iOS target (Views, AppDelegate) |
| `Apps/CLI/LlamaBridgeTest/` | CLI smoke test harness |
| `Frameworks/xcframeworks/` | Vendored `llama.xcframework` (arm64 only) |
| `NoesisNoemaTests/` | XCTest target (partially wired — see memory) |
| `Tests/RAG/` | Logic-level RAG unit tests |

### Swift packages / SPM

No `Package.swift` is present. All dependencies are vendored:

- `llama.xcframework` — embedded in `Frameworks/xcframeworks/`, linked by Xcode project
- No remote Swift packages

### App entry points

| Target | Entry point |
|--------|-------------|
| macOS | `Shared/NoesisNoemaApp.swift` (`@main NoesisNoemaApp`) |
| iOS | `Apps/iOS/NoesisNoemaMobile/NoesisNoemaMobileApp.swift` |
| CLI | `Apps/CLI/LlamaBridgeTest/main.swift` |

Both app targets instantiate `HybridExecutionCoordinator()` at launch and thread it down through the view hierarchy.

### Current layering

```
┌────────────────────────────────────────────────────────┐
│  UI Layer (SwiftUI Views)                              │
│  macOS: DesktopChatView / DesktopRootView             │
│  iOS:   ChatView / MobileHomeView / TabRootView       │
│  Shared: MinimalClientView (#if DEBUG only in prod)   │
└──────────────────────┬─────────────────────────────────┘
                       │ ExecutionCoordinating protocol
┌──────────────────────▼─────────────────────────────────┐
│  HybridExecutionCoordinator (canonical coordinator)    │
│  • Builds NoemaQuestion + RuntimeState                 │
│  • PolicyEngine.evaluate()                             │
│  • applyOverride() (HumanOverrideMode)                │
│  • Router.route() → RoutingDecision                    │
│  • Privacy enforcement Step 4.5                        │
│  • TraceCollector.record()                             │
└───────┬───────────────────────────────────┬────────────┘
        │ .local                            │ .cloud
┌───────▼───────────┐             ┌─────────▼──────────┐
│  LocalExecutor    │             │  AgentExecutor      │
│  • VectorStore    │             │  • AgentClient      │
│  • LocalRetriever │             │    (protocol)       │
│  • DeepSearch     │             │  • HTTPAgentClient  │
│  • LLMModel       │             │    (concrete impl)  │
│    .generateAsync │             │    POST /v1/query   │
└───────────────────┘             └────────────────────┘
```

---

## 2. Current Execution Flow

The active production request lifecycle:

```
User input (keyboard submit)
  ↓
View (ChatView / DesktopChatView / MobileHomeView)
  ↓ NoemaRequest(query:, sessionId:, history:)
HybridExecutionCoordinator.execute(request:overrideMode:)
  ↓
Step 1: buildRuntimeState(overrideMode:) → RuntimeState
  ↓
Step 2: buildQuestion(from:) → NoemaQuestion
  ↓
Step 3: PolicyEngine.evaluate(question:runtimeState:rules:) → PolicyEvaluationResult
  ↓
Step 4: applyOverride(_:override:) — replaces effectiveAction if HumanOverrideMode ≠ .none
  ↓
Step 5: Router.route / routeWithTrace → RoutingDecision
  │         ├─ STEP 1: policyResult.effectiveAction (.block / .forceLocal / .forceCloud / .allow)
  │         ├─ STEP 2: question.privacyLevel (.local / .cloud / .auto)
  │         └─ STEP 3: auto mode (tokenCount vs tokenThreshold, localModelAvailable)
  ↓
Step 6: Select executor (routeTarget == .local → LocalExecutor; .cloud → AgentExecutor)
  ↓
Step 6.5: evaluatePrivacyStep45() — non-bypassable local-only enforcement
  ↓
Step 7: executor.execute(query:sessionId:history:)
  │
  ├─ LOCAL PATH: LocalExecutor
  │     ├─ VectorStore.retrieve (topK=3/5)  [or DeepSearch if opt-in]
  │     ├─ context truncation (n_ctx budget)
  │     └─ LLMModel.generateAsync(prompt:context:history:)
  │
  └─ CLOUD PATH: AgentExecutor → HTTPAgentClient.query()
        └─ POST http://localhost:8080/v1/query  { query, session_id }
  ↓
Step 8: TraceCollector.shared.record(ExecutionTrace)
  ↓
NoemaResponse(text:sources:sessionId:)
  ↓
View renders answer + citations
```

**Responsible types:**

| Step | Type | File |
|------|------|------|
| Entry point | `HybridExecutionCoordinator` | `Shared/Runtime/Execution/HybridExecutionCoordinator.swift` |
| Policy | `PolicyEngine` | `Shared/Policy/PolicyEngine.swift` |
| Routing | `Router` | `Shared/Routing/Router.swift` |
| Local retrieval | `LocalRetriever` / `DeepSearch` | `Shared/RAG/LocalRetriever.swift`, `Shared/RAG/DeepSearch.swift` |
| Local inference | `LLMModel` → `NoesisCompletionPipeline` | `Shared/LLMModel.swift`, `Shared/Llama/NoesisCompletionPipeline.swift` |
| Cloud I/O | `HTTPAgentClient` | `Shared/Runtime/Networking/HTTPAgentClient.swift` |
| Trace | `TraceCollector` | `Shared/Runtime/Tracing/TraceCollector.swift` |
| Request/Response | `NoemaRequest`, `NoemaResponse` | `Shared/Execution/ExecutionCoordinator.swift` |

---

## 3. Existing Routing Remnants

**Finding: all routing code is ACTIVE, not dormant remnants.**

The following types exist and are wired to all production execution paths:

### 3a. `Shared/Routing/` — all active

| File | Contents | Status |
|------|----------|--------|
| `Router.swift` | Deterministic pure-function router; 3 evaluation steps: Policy → Privacy → Auto | **Active (canonical)** |
| `NoemaQuestion.swift` | Typed question with `privacyLevel`, `toolRequired`, `privacySensitive`, `lowLatencyPreferred` | **Active** |
| `RoutingDecision.swift` | `routeTarget` (local/cloud), `model`, `ruleId`, `fallbackAllowed`, `requiresConfirmation` | **Active** |
| `RuntimeState.swift` | `networkState`, `localModelCapability`, `tokenThreshold`, `cloudModelName`, `debugMode`, `overrideMode` | **Active** |
| `HumanOverrideMode.swift` | `.none` / `.forceLocal` / `.forceRemote` — runtime control, not request content | **Active** |
| `RoutingRuleId.swift` | `POLICY_BLOCK`, `POLICY_FORCE_LOCAL`, `POLICY_FORCE_CLOUD`, `PRIVACY_LOCAL`, `PRIVACY_CLOUD`, `AUTO_LOCAL`, `AUTO_CLOUD` | **Active** |
| `RoutingError.swift` | `networkUnavailable`, `policyViolation`, `invalidConfiguration` | **Active** |
| `PolicyEvaluationResult.swift` | Policy outcome carrying `effectiveAction`, `appliedConstraints`, `requiresConfirmation` | **Active** |

### 3b. `Shared/Runtime/` — all active

| File | Contents | Status |
|------|----------|--------|
| `HybridExecutionCoordinator.swift` | Canonical orchestrator (all production flows route here) | **Active** |
| `LocalExecutor.swift` | On-device RAG+LLM executor; no network I/O | **Active** |
| `AgentExecutor.swift` | Cloud executor; delegates to `AgentClient` | **Active** |
| `AgentClient.swift` | Protocol: `query(query:sessionId:) async throws -> String` | **Active** |
| `HTTPAgentClient.swift` | Concrete: POST to `http://localhost:8080/v1/query`; URLSession | **Active** |
| `ExecutorProtocol.swift` | `Executor` protocol with history-aware default extension | **Active** |
| `ExecutionResult.swift` | Immutable result: `output`, `sources` (chunks), `traceId` | **Active** |
| `ExecutionTrace.swift` | Full audit record per execution | **Active** |
| `TraceCollector.swift` | Singleton actor; writes to `FileTraceSink` | **Active** |

### 3c. `Shared/Execution/ExecutionCoordinator.swift` — legacy / dormant

- Present, compiles, referenced only by test suite (`ExecutionCoordinatorTests`)
- Has `TODO R4: this Preview-only coordinator … slated for removal in R4 (ADR-0008)` comment
- Cloud execution is an unimplemented stub (`cloudExecutionNotImplemented = networkUnavailable`)
- **NOT wired to any production UI flow** — `HybridExecutionCoordinator` replaced it

### 3d. `Shared/Utils/ConnectivityGuard.swift` — active

- `ConnectivityGuard.canPerformRemoteCall()` reads `AppSettings.shared.offline`
- `ConnectivityGuard.requireOnline()` throws if offline
- Called from Google Drive service; **not yet called from the HTTP agent path** — the offline guard in the agent path is currently the Router's `networkState == .online` check (hardcoded `.online` in `HybridExecutionCoordinator.buildRuntimeState()`)

### 3e. `AppSettings.offline` — active but partially wired

- `AppSettings.shared.offline: Bool` (default `false`) drives the "Offline" toggle in both Settings views
- Displayed in UI with a "Local Only" badge when both offline=true and `ModelManager.shared.isFullyLocal()`
- `ConnectivityGuard` reads it — but `HybridExecutionCoordinator.buildRuntimeState()` currently hard-codes `networkState: .online` rather than reading the flag
- This is the existing feature flag infrastructure for the offline/local-only mode

---

## 4. Simple UI Remnants

### `Shared/UI/MinimalClientView.swift` — dormant in production, active in DEBUG

**What it is:** The EPIC1 "X-1 Minimal Client Interface" — a cross-platform SwiftUI view with a TextEditor, Submit button, and response display. Labelled "X-1 Minimal Client Interface" in its title bar.

**Files:**

| File | Contents |
|------|----------|
| `Shared/UI/MinimalClientView.swift` | `MinimalClientView` + `MinimalClientViewModel` |

**Current status:**

| Platform | Where it appears | Active? |
|----------|-----------------|---------|
| iOS | `Apps/iOS/NoesisNoemaMobile/Views/SettingsView.swift` — `#if DEBUG` sheet at "Advanced ▸ Open Minimal Client" | DEBUG only |
| macOS | `Apps/macOS/NoesisNoema/Views/DesktopSettingsView.swift` — `#if DEBUG` `debugSection` sheet | DEBUG only |
| macOS Shared | `Shared/NoesisNoemaApp.swift` comment: "MinimalClientView remains reachable from Settings ▸ Advanced under #if DEBUG, and the retired Shared/ContentView.swift is no longer referenced" | DEBUG only |

**Architecture:** `MinimalClientView` injects `ExecutionCoordinating` and calls `executionCoordinator.execute(request:)`. It does not bypass the routing layer. A fresh `HybridExecutionCoordinator()` is instantiated at each presentation because the coordinator is stateless.

**Can it serve as a future Control Panel?** Yes. It already:
- Accepts any `ExecutionCoordinating` via dependency injection
- Calls the full routing pipeline (PolicyEngine → Router → Executor)
- Is cross-platform SwiftUI
- Has no RAGpack or model-specific UI — it is a pure question/answer surface

The main gap is that it exposes no `HumanOverrideMode` controls (force-local / force-remote). Adding a picker for those is the only UI change required to make it a routing control panel.

### `Shared/ContentView.swift` — retired / dormant

- Now conditionally compiled with `#if os(macOS)` but **not referenced from `@main`** (per comment in `NoesisNoemaApp.swift`)
- Still compiles but calls `ModelManager.shared.generateAsyncAnswer()` directly — bypasses the hybrid routing layer
- Functions as a historical record of the pre-EPIC4 architecture; safe to delete in a future cleanup

---

## 5. Integration Seam

**Target:** Inserting `POST /v1/route` (noema-agent typed route contract) without changing the local RAG pipeline.

**Safest insertion point: `HTTPAgentClient.query()`**

```
Shared/Runtime/Networking/HTTPAgentClient.swift
```

**Why this is the seam:**

1. `HTTPAgentClient` is the *only* component in the codebase that makes outbound HTTP calls to a noema-agent endpoint
2. It is behind the `AgentClient` protocol — the rest of the runtime sees only the protocol, not the concrete HTTP logic
3. The `AgentExecutor` delegates all network I/O here; it contains no HTTP knowledge itself
4. The `Router` has already decided to route to cloud before this point — changing the URL or payload schema inside `HTTPAgentClient` does not affect any routing, policy, or local-path logic
5. `AppSettings.offline` → `ConnectivityGuard` can gate this call before it fires

**What the seam looks like today (endpoint / payload):**

```
POST http://localhost:8080/v1/query
Content-Type: application/json
{ "query": String, "session_id": UUID }
→ returns: plain String
```

**What the route contract would change:**

Only the URL path (`/v1/query` → `/v1/route`) and possibly the payload schema. `HTTPAgentClient` is the sole owner of that surface. No other type needs to change to redirect to the route contract.

**The `AgentClient` protocol** is also exactly the right shape for a future typed `RouteClient` protocol, since it is already:
- A pure I/O component (no business logic)
- Dependency-injected into `AgentExecutor`
- Protocol-defined (can be swapped without touching `AgentExecutor` or `HybridExecutionCoordinator`)

---

## 6. Local-Only Guarantees

### 6a. Primary local-only enforcement

| Mechanism | Where | Guarantee |
|-----------|-------|-----------|
| `Router.route()` AUTO_LOCAL | `Shared/Routing/Router.swift:196–212` | When token count ≤ threshold AND local model available → routes to `.local` |
| `HumanOverrideMode.forceLocal` | `Shared/Routing/HumanOverrideMode.swift` | User or test can force-local regardless of policy |
| Privacy enforcement Step 4.5 | `HybridExecutionCoordinator.evaluatePrivacyStep45()` | Non-bypassable: `privacyLevel == .local` → refuses cloud executor even if Router or policy would have routed cloud |
| `AppSettings.offline` | `Shared/AppSettings.swift` | Toggle is exposed in both Settings UIs; `ConnectivityGuard` reads it |

### 6b. Local RAG pipeline has no network I/O

- `LocalExecutor.execute()` is documented: "This path performs no network I/O. Retrieval is local (VectorStore) and inference is local (llama.cpp)."
- `VectorStore` — in-memory store populated from RAGpack import; no network
- `LlamaInferenceEngine` / `NoesisCompletionPipeline` — llama.cpp FFI; no network
- `EmbeddingModel` / `LlamaEmbeddingContext` — embedding via llama.cpp; no network

### 6c. No hidden server dependency

- The app builds and runs fully without a running noema-agent process
- `HTTPAgentClient` is only invoked when `Router` returns `routeTarget == .cloud`
- Default `RuntimeState` in `HybridExecutionCoordinator.buildRuntimeState()` sets `networkState: .online` and `tokenThreshold: 4096` — which means short local queries route to `.local` by default via `AUTO_LOCAL`
- No startup ping, no health-check dependency, no daemon

### 6d. Networking is optional, not required

- `AgentExecutor` + `HTTPAgentClient` compile and exist but are only reached if the Router decides `.cloud`
- The app has never shipped a build that successfully completes the cloud path end-to-end (the noema-agent endpoint has been `localhost:8080` — a developer-only value)
- `ConnectivityGuard.requireOnline()` exists as a call-site guard; the offline flag in Settings is user-facing

### 6e. Private corpus remains local

- RAGpack files are imported through `DocumentManager.processRAGpackImport` into `VectorStore.shared` (in-memory + persisted locally)
- No corpus data is sent to `HTTPAgentClient` — only the user query string and a session UUID are transmitted
- Embeddings (768-dim float32 from nomic-embed-text-v1.5) live entirely in device memory / local files

---

## 7. ADR-0001 Capability Comparison

> **Note:** No `ADR-0001.md` file is present in the `docs/` tree of the current branch. The architectural constitution is embedded in `docs/architecture/epic4-implementation-guidelines.md` as ADR-0000. The capabilities below are assessed against the ADR-0001 intent described in the issue (local cognition node, optional server connection, route contract seam, etc.) and the confirmed noema-agent audit findings (routing responsibility belongs to client; typed route contract; local-only default).

| Capability | Current State | Missing | Risk | Priority |
|-----------|--------------|---------|------|----------|
| **Local cognition node** | Fully implemented. `LocalExecutor` runs RAG + llama.cpp on-device. Privacy enforcement (Step 4.5) is non-bypassable. | Nothing structural | None | N/A (done) |
| **Optional server connection** | `HTTPAgentClient` exists and targets `localhost:8080/v1/query`. Cloud path is compilable but has never been exercised against a live noema-agent. | `AppSettings.offline` is not yet wired into `HybridExecutionCoordinator.buildRuntimeState()` (hardcodes `networkState: .online`) | Low — cloud path only reached if Router decides `.cloud` | Medium |
| **Feature flag seam** | `AppSettings.offline` (Bool, UserDefaults-backed) exists and is exposed in both Settings UIs. "Local Only" badge is shown when offline && fully local. | `buildRuntimeState()` does not read the flag; `ConnectivityGuard` exists but is not in the agent execution path | Medium — offline toggle has no effect on the routing decision today | High |
| **Route contract seam** | `AgentClient` protocol + `HTTPAgentClient` concrete class exist. The protocol is a clean I/O boundary. Endpoint is `localhost:8080/v1/query` (not `/v1/route`). | Typed route contract DTO (request/response structs matching noema-agent's `/v1/route` schema) | Low — structure is ready; only the endpoint and payload schema need updating | High |
| **UI control surface** | `MinimalClientView` exists and is accessible in DEBUG builds (Settings ▸ Advanced on both platforms). Wired to full routing pipeline. | No `HumanOverrideMode` picker exposed in `MinimalClientView`; no force-local/force-remote controls visible in production | Low — control surface exists; only the override controls are absent | Medium |
| **Audit logging** | `TraceCollector` + `FileTraceSink` + `ExecutionTrace` write a full structured trace per execution (route, policy, routing steps, privacy, duration, error). | Traces are written locally; no export or query UI exposed to users | Low — logging is comprehensive for debugging | Low |
| **Local-only mode** | `AppSettings.offline` toggle is present. Privacy `.local` + Step 4.5 enforcement is non-bypassable. `LocalExecutor` has no network calls. | `buildRuntimeState()` hardcodes `networkState: .online` regardless of `AppSettings.offline` | Medium — the flag exists but is inert in the routing path today | High |
| **Privacy boundary** | Hard-enforced at HEC Step 6.5 (`evaluatePrivacyStep45`). Privacy-local requests that would route cloud are refused with a structured throw. Corpus data never leaves device. | None structural | None | N/A (done) |

---

## 8. Recommendation

**Recommended next task: Wire `AppSettings.offline` into `HybridExecutionCoordinator.buildRuntimeState()`**

**Justification:**

This is the highest-leverage minimal change that closes the largest open gap without modifying the routing logic, adding networking, or creating new abstractions.

**Current gap:** `HybridExecutionCoordinator.buildRuntimeState()` (`Shared/Runtime/Execution/HybridExecutionCoordinator.swift:305–318`) hardcodes `networkState: .online`. The user-facing "Offline" toggle (`AppSettings.shared.offline`) exists, is visible in both Settings UIs, and shows a "Local Only" badge — but has no effect on the actual routing decision today. A user who enables Offline expects local-only routing; the current code continues to route `.cloud` if the query exceeds the token threshold.

**Scope of the change:**

```swift
// HybridExecutionCoordinator.buildRuntimeState()
// Replace:
networkState: .online,
// With:
networkState: AppSettings.shared.offline ? .offline : .online,
```

This single substitution:
- Connects the existing feature flag to the existing routing decision
- Makes the existing "Local Only" badge semantically accurate
- Does not add any new types, protocols, abstractions, or dependencies
- Does not touch the routing logic, policy engine, or local executor
- Is the natural precursor to all other integration work (a live noema-agent connection can only be safely wired once the offline guard is effective)

**Why not the route contract seam instead?**

The route contract (`POST /v1/route` in `HTTPAgentClient`) is a meaningful next step, but it depends on a running noema-agent instance and a confirmed payload schema. The offline flag fix is prerequisite work: it ensures the local-only invariant holds for all users before any cloud integration is tested or shipped. An optional server connection is only safe to add when the offline default is enforced by the code, not just displayed in the UI.

---

## Appendix A: File inventory — routing-related symbols

| Symbol | Kind | File |
|--------|------|------|
| `Router` | struct | `Shared/Routing/Router.swift` |
| `NoemaQuestion` | struct | `Shared/Routing/NoemaQuestion.swift` |
| `RoutingDecision` | struct | `Shared/Routing/RoutingDecision.swift` |
| `ExecutionRoute` | enum | `Shared/Routing/RoutingDecision.swift` |
| `RuntimeState` | struct | `Shared/Routing/RuntimeState.swift` |
| `NetworkState` | enum | `Shared/Routing/RuntimeState.swift` |
| `LocalModelCapability` | struct | `Shared/Routing/RuntimeState.swift` |
| `HumanOverrideMode` | enum | `Shared/Routing/HumanOverrideMode.swift` |
| `RoutingRuleId` | enum | `Shared/Routing/RoutingRuleId.swift` |
| `RoutingError` | enum | `Shared/Routing/RoutingError.swift` |
| `PolicyEvaluationResult` | struct | `Shared/Routing/PolicyEvaluationResult.swift` |
| `HybridExecutionCoordinator` | final class | `Shared/Runtime/Execution/HybridExecutionCoordinator.swift` |
| `LocalExecutor` | final class | `Shared/Runtime/Executors/LocalExecutor.swift` |
| `AgentExecutor` | final class | `Shared/Runtime/Executors/AgentExecutor.swift` |
| `AgentClient` | protocol | `Shared/Runtime/Executors/AgentClient.swift` |
| `HTTPAgentClient` | final class | `Shared/Runtime/Networking/HTTPAgentClient.swift` |
| `Executor` | protocol | `Shared/Runtime/Executors/ExecutorProtocol.swift` |
| `ExecutionResult` | struct | `Shared/Runtime/Executors/ExecutionResult.swift` |
| `ExecutionTrace` | struct | `Shared/Runtime/Tracing/ExecutionTrace.swift` |
| `TraceCollector` | actor | `Shared/Runtime/Tracing/TraceCollector.swift` |
| `ConnectivityGuard` | struct | `Shared/Utils/ConnectivityGuard.swift` |
| `AppSettings.offline` | @Published Bool | `Shared/AppSettings.swift` |
| `MinimalClientView` | struct (View) | `Shared/UI/MinimalClientView.swift` |
| `ExecutionCoordinator` | final class (legacy) | `Shared/Execution/ExecutionCoordinator.swift` |

---

## Appendix B: Search results — no hits for server/API/HTTP outside known files

Searched for: `URLSession`, `URLRequest`, `http`, `HTTP`, `API`, `Server`, `Network`, `URLError` across all `.swift` files excluding the known networking files.

Hits:

| Term | Files hit |
|------|-----------|
| `URLSession` | `HTTPAgentClient.swift`, `GoogleDriveService.swift`, `GoogleDriveDownloader.swift` |
| `URLRequest` | `HTTPAgentClient.swift`, `GoogleDriveService.swift`, `GoogleDriveDownloader.swift` |
| `ConnectivityGuard` | `ConnectivityGuard.swift`, `GoogleDriveService.swift` |

**Google Drive services** (`GoogleDriveService.swift`, `GoogleDriveDownloader.swift`) use `URLSession` for RAGpack download from Google Drive (user-initiated model import). They are guarded by `ConnectivityGuard.requireOnline()`. This is the only other network usage in the codebase and is not part of the inference or routing path.

No hidden server dependencies or undiscovered HTTP clients exist in the Swift source tree.
