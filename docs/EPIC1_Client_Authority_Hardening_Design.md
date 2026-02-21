# EPIC 1 — Client Authority Hardening (Phase 2)

**Project**: NoesisNoema (Swift Client App)
**RAGfish Core Version**: 1.0.0
**Document Status**: Design Blueprint
**Created**: 2026-02-21
**Author**: System Architecture Team

---

## Document Purpose

This document translates RAGfish core design principles into a concrete implementation plan for the NoesisNoema Swift client. It serves as the architectural blueprint for implementing **Client Authority Hardening** — ensuring that all AI execution is initiated, controlled, and visible to the human user.

This is a **pre-implementation design document**. No code is written until this design is reviewed and approved.

---

# SECTION 1 — Architectural Interpretation

## 1.1 What is Client Authority?

**Client Authority** is the architectural principle that **all execution decisions originate from and are controlled by the client**, not the server.

In RAGfish, Client Authority means:

1. **The client owns routing decisions** — The client determines whether execution happens locally or in the cloud.
2. **The server never self-routes** — The server is a stateless execution engine that receives explicit instructions.
3. **Every execution is human-triggered** — No background autonomous behavior is permitted.
4. **Execution is deterministic** — Given the same inputs and state, routing always produces the same output.
5. **Execution is visible** — Every decision, execution, and result is logged and inspectable.

### Why This Matters

Traditional cloud AI systems operate as black boxes:
- Users submit prompts and receive outputs with no visibility into the decision-making process.
- Servers autonomously decide which model to use, whether to escalate execution, or how to handle failures.
- Privacy boundaries are opaque and often violated without user knowledge.

**Client Authority inverts this power dynamic:**
- The user's device is the source of truth for all decisions.
- The server becomes a controlled execution environment, not an autonomous agent.
- Privacy is enforced structurally, not through policy promises.

---

## 1.2 Why Routing Must Live Client-Side

Routing is the act of determining **where and how** a user's question will be executed:
- **Local execution**: On-device model inference (private, offline-capable, but limited capacity)
- **Cloud execution**: Remote model inference (powerful, but requires network and data transmission)

### Why Client-Side Routing is Non-Negotiable

1. **Human Controllability**
   The user must control privacy boundaries. If routing happens server-side, the server could silently escalate private data to cloud execution without user consent or knowledge.

2. **Deterministic Behavior**
   Client-side routing allows the user to inspect and predict system behavior. Server-side routing introduces probabilistic or opaque decision-making that the user cannot audit.

3. **No Hidden Escalation**
   If the server makes routing decisions, it could dynamically switch models, escalate to more powerful (and expensive) infrastructure, or change behavior without user visibility. This violates the principle of human sovereignty.

4. **Privacy Enforcement**
   When `privacy_level == "local"`, the system must **guarantee zero network transmission**. Only client-side routing can enforce this structurally — the client simply never sends the request. Server-side routing would require trusting the server to honor the privacy constraint.

### Design Consequence for NoesisNoema

- The Swift client must implement a **Router** component that evaluates routing rules deterministically.
- The Router must execute **before** any network call is made.
- The Router's decision must be **logged locally** and displayed in the UI.
- The server receives only the routing decision (task_type) and the minimal payload required for execution — it never receives enough information to make routing decisions itself.

---

## 1.3 Why Server Must Not Self-Route

The server in RAGfish is an **execution boundary**, not a decision boundary.

### Server Role (Permitted)
- Receive a structured request with explicit `task_type` (routing decision)
- Execute the specified task using the designated model
- Return a structured response with `trace_id`
- Validate that the request is well-formed (schema compliance)

### Server Role (Forbidden)
- Select which model to use based on prompt analysis
- Escalate execution from one model to another without client approval
- Make routing decisions based on server-side heuristics
- Autonomously retry or fallback to different execution paths

### Why This Constraint Exists

If the server can self-route:
1. **Privacy boundaries become unenforceable** — The server could decide to send data to a third-party model provider, even if the client requested local execution.
2. **Execution becomes non-deterministic** — The same request could produce different behaviors depending on server-side state, load balancing, or model availability.
3. **Human sovereignty is lost** — The user no longer controls the system; the server does.

### Design Consequence for NoesisNoema

- The server API must accept a `task_type` field that explicitly specifies the execution route.
- The server must **reject requests without a valid task_type**.
- If the server cannot execute the requested task_type (e.g., model unavailable), it must return a structured error — not silently fallback to another model.

---

## 1.4 What "Execution Boundary Ownership" Means

An **execution boundary** is the point at which control transfers from one system component to another.

In RAGfish:
- **Client Boundary**: User input → Routing decision → Invocation
- **Network Boundary**: Client → Server (data crosses trust zone)
- **Execution Boundary**: Server receives request → Executes task → Returns response

### Ownership Rules

1. **The client owns the decision boundary** — Routing happens client-side.
2. **The server owns the execution boundary** — Model inference happens server-side (for cloud routes).
3. **No component may cross its boundary without explicit contract** — The server cannot decide to route; the client cannot execute cloud models directly.

### Invocation Contract

Every execution must be bound to a single **Invocation**:
- One human-triggered action
- One Question object
- One routing decision
- One execution attempt
- One Response object

**Forbidden behaviors:**
- Background execution (server or client)
- Recursive self-invocation
- Auto-triggered follow-up executions
- Silent retries (except explicit network retry policy)
- Spawning new Question objects without user action

### Design Consequence for NoesisNoema

- The client must create a **Question object** with a unique `question_id` for every user-submitted prompt.
- The client must track the lifecycle: `created → routed → executed → completed/failed`.
- The client must **never trigger execution without explicit user action** (no background processing).
- All state transitions must be logged with `trace_id`.

---

## 1.5 Why All Execution Must Be Visible

**Observability is not optional** — it is a foundational design requirement.

### What Must Be Visible

1. **Routing Decision**
   - Which route was chosen (local or cloud)?
   - Why was this route chosen (which rule applied)?
   - Which model was selected?
   - Was fallback permitted?

2. **Execution Attempt**
   - When did execution start?
   - What was the result (success/error)?
   - What was the latency?
   - Was fallback used?

3. **Privacy Enforcement**
   - Was network transmission blocked due to `privacy_level == "local"`?
   - Which constraints were applied?

4. **Error Details**
   - What went wrong?
   - What was the error code?
   - Is the error recoverable?
   - What is the `trace_id` for debugging?

### Why Visibility Matters

1. **Trust** — Users can verify that their privacy constraints are being honored.
2. **Debugging** — Developers and users can understand why something failed.
3. **Auditability** — All execution can be traced and reconstructed.
4. **Compliance** — Regulatory requirements may mandate execution logs.

### Privacy and Visibility Trade-offs

- **Production logs must NOT include raw prompt content by default** (to prevent accidental exposure).
- Logs may include:
  - `content_hash` (stable hash of prompt)
  - `content_length` (token count)
  - Truncated preview (first N characters, configurable)
- **User-facing logs must show high-level metadata**, not internal stack traces.

### Design Consequence for NoesisNoema

- The client must maintain an **Execution History** feature that displays:
  - Timestamp
  - Route (local/cloud)
  - Model used
  - Fallback status
  - Error code (if any)
  - `trace_id`
- The UI must surface this information **non-intrusively** (e.g., expandable detail view).
- Logs must be stored securely on-device (not transmitted to server by default).

---

# SECTION 2 — Explicit Routing Logic

## 2.1 Routing Decision Inputs

The Router is a **pure decision function**. It takes structured inputs and produces a deterministic output.

### Primary Inputs (from NoemaQuestion object)

```swift
struct NoemaQuestion {
    let id: UUID                    // Unique question identifier
    let content: String             // User prompt text
    let privacyLevel: PrivacyLevel  // "local" | "cloud" | "auto"
    let intent: Intent?             // Optional intent classification
    let constraints: [Constraint]?  // Optional user-defined constraints
    let sessionId: UUID             // Active session identifier
    let timestamp: Date             // Creation timestamp
}

enum PrivacyLevel: String {
    case local = "local"   // Force local execution
    case cloud = "cloud"   // Force cloud execution
    case auto = "auto"     // Allow Router to decide
}

enum Intent: String {
    case informational  // Simple factual queries
    case analytical     // Reasoning, analysis
    case retrieval      // RAG-based context retrieval
}
```

### Runtime State Inputs

```swift
struct RuntimeState {
    let localModelCapability: LocalModelCapability
    let networkState: NetworkState
    let tokenThreshold: Int  // Default: 4096
}

struct LocalModelCapability {
    let modelName: String
    let maxTokens: Int
    let supportedIntents: [Intent]
    let available: Bool
}

enum NetworkState {
    case online    // Network confirmed
    case offline   // Network unavailable
    case degraded  // High latency
}
```

### Constraint Inputs (Section 3)

User-defined constraints that override default routing behavior (detailed in Section 3).

---

## 2.2 Routing Decision Output (task_type)

The Router produces a **RoutingDecision** that explicitly states how execution should proceed.

```swift
struct RoutingDecision {
    let route: ExecutionRoute       // "local" | "cloud"
    let model: String               // Explicit model identifier
    let reason: String              // Human-readable explanation
    let ruleId: String              // Which routing rule was applied
    let fallbackAllowed: Bool       // Can fallback to cloud if local fails?
    let confidence: Double          // Always 1.0 (deterministic)
    let timestamp: Date
    let traceId: UUID               // For observability
}

enum ExecutionRoute: String {
    case local = "local"
    case cloud = "cloud"
}
```

### task_type Encoding

The `task_type` is sent to the server to specify the execution route:

```swift
enum TaskType: String, Codable {
    case localLLM = "local_llm"
    case cloudLLM = "cloud_llm"
    case ragRetrieval = "rag_retrieval"
    case hybridRAG = "hybrid_rag"
}
```

The server uses `task_type` to select the appropriate execution path. It does **not** re-interpret the prompt to make this decision.

---

## 2.3 Deterministic Routing Rules

Routing follows **strict priority order**. The first matching rule is applied.

### Rule 1 — Privacy Enforcement (Highest Priority)

```swift
// If user explicitly requests local execution
if question.privacyLevel == .local {
    return RoutingDecision(
        route: .local,
        model: runtimeState.localModelCapability.modelName,
        reason: "Privacy level set to local",
        ruleId: "PRIVACY_LOCAL",
        fallbackAllowed: false,
        confidence: 1.0,
        timestamp: Date(),
        traceId: UUID()
    )
}

// If user explicitly requests cloud execution
if question.privacyLevel == .cloud {
    // Only proceed if network is available
    guard runtimeState.networkState == .online else {
        throw RoutingError.networkUnavailable
    }

    return RoutingDecision(
        route: .cloud,
        model: "gpt-4", // Or configured cloud model
        reason: "Privacy level set to cloud",
        ruleId: "PRIVACY_CLOUD",
        fallbackAllowed: false,
        confidence: 1.0,
        timestamp: Date(),
        traceId: UUID()
    )
}
```

**Key Constraints:**
- When `privacy_level == .local`, network transmission is **structurally impossible** (the request never leaves the device).
- When `privacy_level == .cloud`, local fallback is **forbidden** (user explicitly chose cloud).
- `fallbackAllowed = false` for explicit privacy constraints.

---

### Rule 2 — Auto Mode Routing

When `privacy_level == .auto`, the Router evaluates multiple factors to determine the optimal route.

```swift
if question.privacyLevel == .auto {
    // Step 1: Estimate token count
    let tokenCount = estimateTokenCount(question.content)

    // Step 2: Check local model capability
    let localModelAvailable = runtimeState.localModelCapability.available

    // Step 3: Check if intent is supported locally
    var intentSupportedLocally = true
    if let intent = question.intent {
        intentSupportedLocally = runtimeState.localModelCapability
            .supportedIntents.contains(intent)
    }

    // Step 4: Apply routing logic
    if tokenCount <= runtimeState.tokenThreshold
        && localModelAvailable
        && intentSupportedLocally {

        return RoutingDecision(
            route: .local,
            model: runtimeState.localModelCapability.modelName,
            reason: "Token count within threshold, local model capable",
            ruleId: "AUTO_LOCAL",
            fallbackAllowed: true,  // Can fallback to cloud if local fails
            confidence: 1.0,
            timestamp: Date(),
            traceId: UUID()
        )
    } else {
        // Default to cloud for auto mode
        guard runtimeState.networkState == .online else {
            throw RoutingError.networkUnavailable
        }

        return RoutingDecision(
            route: .cloud,
            model: "gpt-4",
            reason: "Token count exceeds threshold or local model insufficient",
            ruleId: "AUTO_CLOUD",
            fallbackAllowed: false,
            confidence: 1.0,
            timestamp: Date(),
            traceId: UUID()
        )
    }
}
```

**Decision Factors:**
1. **Token Count** — Large prompts exceed local model capacity.
2. **Intent Support** — Local model may not support complex analytical tasks.
3. **Model Availability** — Local model may not be downloaded or initialized.
4. **Network State** — Cloud route requires network connectivity.

---

### Rule 3 — Local Failure Handling

If local execution fails and fallback is allowed:

```swift
func handleLocalFailure(
    decision: RoutingDecision,
    error: ExecutionError
) -> RoutingDecision {
    guard decision.fallbackAllowed else {
        // If fallback not allowed, return error to user
        throw error
    }

    // Log the escalation
    logEscalation(from: .local, to: .cloud, reason: error.localizedDescription)

    // Create new routing decision for cloud fallback
    return RoutingDecision(
        route: .cloud,
        model: "gpt-4",
        reason: "Local execution failed: \(error.localizedDescription)",
        ruleId: "LOCAL_FAILURE_FALLBACK",
        fallbackAllowed: false,  // No further fallback
        confidence: 1.0,
        timestamp: Date(),
        traceId: decision.traceId  // Preserve original trace_id
    )
}
```

**Critical Rules:**
- Fallback only occurs if `fallbackAllowed == true`.
- Escalation is **logged** with original `trace_id`.
- User is notified that fallback occurred (UI indication).

---

### Rule 4 — Cloud Failure Handling

If cloud execution fails, **no automatic fallback** is permitted.

```swift
func handleCloudFailure(error: ExecutionError) {
    // Return structured error to user
    return StructuredError(
        code: error.code,
        message: error.localizedDescription,
        recoverable: false,
        traceId: error.traceId
    )
}
```

**No Silent Recovery** — The user must explicitly retry or change the routing constraint.

---

## 2.4 No Hidden Model Selection

The Router must **never** perform hidden model selection based on prompt analysis.

### Forbidden Behaviors

❌ Analyzing prompt content to infer topic and select specialized models
❌ Using sentiment analysis to switch models
❌ Dynamically selecting models based on previous conversation history
❌ Server-side model switching without client knowledge

### Permitted Behaviors

✅ Selecting models based on explicit `intent` field
✅ Selecting models based on token count and capability matching
✅ Selecting models based on user-configured preferences
✅ Returning error if no model can satisfy constraints

### Design Consequence

- Model selection must be **logged** in the `RoutingDecision`.
- The selected model must be **visible in the UI**.
- Users must be able to configure **default model preferences** in settings.

---

## 2.5 Routing Rule Representation and Determinism

This subsection formalizes the deterministic nature of routing and specifies the exact evaluation semantics.

### Routing Rule Identifiers

All routing rules are represented by a strongly-typed enum:

```swift
enum RoutingRuleId: String, Codable {
    case POLICY_BLOCK            // Policy engine blocked execution
    case POLICY_FORCE_LOCAL      // Policy engine forced local route
    case POLICY_FORCE_CLOUD      // Policy engine forced cloud route
    case PRIVACY_LOCAL           // User set privacy_level == .local
    case PRIVACY_CLOUD           // User set privacy_level == .cloud
    case AUTO_LOCAL              // Auto mode selected local (within threshold)
    case AUTO_CLOUD              // Auto mode selected cloud (exceeds threshold)
    case LOCAL_FAILURE_FALLBACK  // Fallback from local to cloud after failure
    case NETWORK_UNAVAILABLE     // Cloud route blocked due to network
}
```

Each rule ID maps to a specific decision path and is logged in `RoutingDecision.ruleId`.

---

### Router as Pure Function

The Router is implemented as a **pure function** with the following signature:

```swift
func route(
    question: NoemaQuestion,
    runtimeState: RuntimeState,
    policyResult: PolicyEvaluationResult
) -> RoutingDecision
```

**Purity Contract:**

This function MUST be:

1. **Deterministic** — Given identical `(question, runtimeState, policyResult)` inputs, the function MUST always return an identical `RoutingDecision` output. No variation is permitted.

2. **Side-effect free** — The function MUST NOT:
   - Perform I/O operations (network calls, disk writes, logging is done by caller)
   - Mutate global state
   - Access mutable external state (current time, random numbers, etc.)
   - Trigger asynchronous operations

3. **Free of randomness** — No probabilistic branching, no `arc4random()`, no ML-based model selection.

4. **Free of time-based branching** — No `Date.now()` comparisons, no timeout logic within the routing function itself.

The Router returns a decision; it does not execute the decision. Execution and logging are the responsibility of the `ExecutionCoordinator`.

---

### Deterministic Evaluation Order

Routing follows a **strict, ordered evaluation sequence**. Each step is evaluated in order, and the first applicable rule terminates evaluation:

```
┌─────────────────────────────────────────────────────────┐
│ ROUTING DECISION TREE (Ordered Evaluation)              │
└─────────────────────────────────────────────────────────┘

Step 1: Apply Policy Decision Engine Result
  ├─ If policyResult.effectiveAction == .block
  │    → Throw PolicyViolationError (no routing decision made)
  │
  ├─ If policyResult.effectiveAction == .forceLocal
  │    → Return RoutingDecision(route: .local, ruleId: POLICY_FORCE_LOCAL, fallbackAllowed: false)
  │
  └─ If policyResult.effectiveAction == .forceCloud
       → Return RoutingDecision(route: .cloud, ruleId: POLICY_FORCE_CLOUD, fallbackAllowed: false)

Step 2: Enforce Privacy Guarantees
  ├─ If question.privacyLevel == .local
  │    → Return RoutingDecision(route: .local, ruleId: PRIVACY_LOCAL, fallbackAllowed: false)
  │    → GUARANTEE: Network request will NEVER be constructed
  │
  └─ If question.privacyLevel == .cloud
       ├─ If runtimeState.networkState != .online
       │    → Throw RoutingError.networkUnavailable
       └─ Else
            → Return RoutingDecision(route: .cloud, ruleId: PRIVACY_CLOUD, fallbackAllowed: false)

Step 3: Apply Auto Mode Logic (privacy_level == .auto)
  ├─ Estimate token count from question.content
  ├─ Check local model availability (runtimeState.localModelCapability.available)
  ├─ Check intent support (question.intent in supportedIntents)
  │
  ├─ If tokenCount <= tokenThreshold AND localAvailable AND intentSupported
  │    → Return RoutingDecision(route: .local, ruleId: AUTO_LOCAL, fallbackAllowed: true)
  │
  └─ Else
       ├─ If runtimeState.networkState != .online
       │    → Throw RoutingError.networkUnavailable
       └─ Else
            → Return RoutingDecision(route: .cloud, ruleId: AUTO_CLOUD, fallbackAllowed: false)

Step 4: Fallback Handling (After Execution Failure)
  ├─ If execution fails AND decision.fallbackAllowed == true
  │    → Create new RoutingDecision(route: .cloud, ruleId: LOCAL_FAILURE_FALLBACK, fallbackAllowed: false)
  │    → Preserve original trace_id
  │    → REQUIRE user confirmation before executing (see Section 5.7)
  │
  └─ If execution fails AND decision.fallbackAllowed == false
       → Throw ExecutionError (no automatic retry)
```

**Evaluation Invariants:**

- Evaluation proceeds **top-to-bottom**; the first matching condition terminates the decision process.
- Policy constraints (Step 1) have **absolute priority** over all other rules.
- Privacy guarantees (Step 2) cannot be bypassed by any subsequent logic.
- Fallback (Step 4) is **not part of the routing function** — it occurs in the `ExecutionCoordinator` after a failed execution attempt.

---

### No Hidden Model Selection

All model selection is **explicit and logged**:

- `RoutingDecision.model` contains the exact model identifier (e.g., `"llama-3.2-8b"`, `"gpt-4"`)
- `RoutingDecision.ruleId` specifies which rule determined the model selection
- Both fields are persisted in `RoutingLog` and displayed in the Execution History UI

**Forbidden:**
- Analyzing prompt content to infer domain and select specialized models
- Using sentiment analysis to switch models
- Selecting models based on conversation history outside the structured `question.intent` field
- Server-side model switching without client knowledge

**Permitted:**
- Selecting models based on explicit `question.intent` field
- Selecting models based on token count and `LocalModelCapability`
- Selecting models based on user-configured preferences (stored in app settings)
- Returning an error if no model can satisfy constraints

---

### Routing Rule to Human-Readable Mapping

For UI display and log inspection, each `RoutingRuleId` maps to a human-readable description:

| Rule ID                 | Human-Readable Description                                   |
|-------------------------|--------------------------------------------------------------|
| `POLICY_BLOCK`          | "Execution blocked by policy constraint"                     |
| `POLICY_FORCE_LOCAL`    | "Policy constraint forced local execution"                   |
| `POLICY_FORCE_CLOUD`    | "Policy constraint forced cloud execution"                   |
| `PRIVACY_LOCAL`         | "User requested local-only execution (privacy constraint)"   |
| `PRIVACY_CLOUD`         | "User requested cloud execution"                             |
| `AUTO_LOCAL`            | "Auto mode: token count within local threshold"              |
| `AUTO_CLOUD`            | "Auto mode: token count exceeds local threshold or local model unavailable" |
| `LOCAL_FAILURE_FALLBACK`| "Local execution failed; fallback to cloud (user confirmed)" |
| `NETWORK_UNAVAILABLE`   | "Cloud execution unavailable: no network connectivity"       |

These descriptions are displayed in:
- Execution History UI (Section 5.3)
- Execution Detail View (Section 5.3)
- Log export files (JSON format)

---

### Determinism Verification

To verify determinism, the following test invariant must hold:

```swift
// Test: Routing determinism
let question = NoemaQuestion(/* fixed values */)
let state = RuntimeState(/* fixed values */)
let policy = PolicyEvaluationResult(/* fixed values */)

let decision1 = route(question: question, runtimeState: state, policyResult: policy)
let decision2 = route(question: question, runtimeState: state, policyResult: policy)

assert(decision1.route == decision2.route)
assert(decision1.ruleId == decision2.ruleId)
assert(decision1.model == decision2.model)
assert(decision1.fallbackAllowed == decision2.fallbackAllowed)
```

This test must pass for all valid input combinations. Any non-deterministic behavior is a contract violation.

---

# SECTION 3 — Policy Decision Engine

## 3.1 Purpose and Scope

The **Policy Decision Engine** is a client-side component that evaluates user-defined constraints **before** routing and execution.

It enforces:
1. **Privacy Constraints** — Prevent unintended data transmission.
2. **Cost Constraints** — Prevent expensive cloud calls.
3. **Performance Constraints** — Set latency expectations.
4. **Intent Constraints** — Restrict certain types of queries.

The Policy Engine operates **deterministically** — given the same constraints and question, it always produces the same evaluation result.

---

## 3.2 Constraint Model

```swift
struct Constraint: Codable, Identifiable {
    let id: UUID
    let name: String
    let type: ConstraintType
    let enabled: Bool
    let priority: Int  // Lower number = higher priority
    let conditions: [ConditionRule]
    let action: ConstraintAction
}

enum ConstraintType: String, Codable {
    case privacy
    case cost
    case performance
    case intent
}

struct ConditionRule: Codable {
    let field: String        // "content", "token_count", "intent"
    let operator: Operator   // "contains", "exceeds", "equals"
    let value: String
}

enum Operator: String, Codable {
    case contains
    case notContains
    case exceeds
    case lessThan
    case equals
    case notEquals
}

enum ConstraintAction: Codable {
    case forceLocal
    case forceCloud
    case block(reason: String)
    case warn(message: String)
    case requireConfirmation(prompt: String)
}
```

---

## 3.3 Example Constraints

### Constraint 1: Block Sensitive Keywords

```swift
Constraint(
    id: UUID(),
    name: "Block Sensitive Data",
    type: .privacy,
    enabled: true,
    priority: 1,
    conditions: [
        ConditionRule(
            field: "content",
            operator: .contains,
            value: "SSN|credit card|password"
        )
    ],
    action: .block(reason: "Prompt contains sensitive data patterns")
)
```

### Constraint 2: Limit Cloud Usage

```swift
Constraint(
    id: UUID(),
    name: "Limit Expensive Cloud Calls",
    type: .cost,
    enabled: true,
    priority: 2,
    conditions: [
        ConditionRule(
            field: "token_count",
            operator: .exceeds,
            value: "8000"
        ),
        ConditionRule(
            field: "privacy_level",
            operator: .equals,
            value: "auto"
        )
    ],
    action: .requireConfirmation(
        prompt: "This query may incur high cloud costs. Continue?"
    )
)
```

### Constraint 3: Force Local for Personal Queries

```swift
Constraint(
    id: UUID(),
    name: "Force Local for Personal Queries",
    type: .privacy,
    enabled: true,
    priority: 1,
    conditions: [
        ConditionRule(
            field: "content",
            operator: .contains,
            value: "my|I am|personal|private"
        )
    ],
    action: .forceLocal
)
```

---

## 3.4 Policy Evaluation Algorithm

```swift
class PolicyDecisionEngine {
    private var constraints: [Constraint] = []

    func evaluateConstraints(
        question: NoemaQuestion,
        runtimeState: RuntimeState
    ) throws -> PolicyEvaluationResult {
        // Sort constraints by priority
        let activeConstraints = constraints
            .filter { $0.enabled }
            .sorted { $0.priority < $1.priority }

        var appliedConstraints: [UUID] = []
        var warnings: [String] = []
        var requiresConfirmation: String? = nil
        var forcedRoute: ExecutionRoute? = nil

        for constraint in activeConstraints {
            // Evaluate condition rules
            let conditionsMet = evaluateConditions(
                constraint.conditions,
                question: question,
                runtimeState: runtimeState
            )

            if conditionsMet {
                appliedConstraints.append(constraint.id)

                switch constraint.action {
                case .block(let reason):
                    throw PolicyViolationError.blocked(
                        reason: reason,
                        constraintId: constraint.id
                    )

                case .forceLocal:
                    forcedRoute = .local

                case .forceCloud:
                    forcedRoute = .cloud

                case .warn(let message):
                    warnings.append(message)

                case .requireConfirmation(let prompt):
                    requiresConfirmation = prompt
                }
            }
        }

        return PolicyEvaluationResult(
            allowed: true,
            appliedConstraints: appliedConstraints,
            forcedRoute: forcedRoute,
            warnings: warnings,
            requiresConfirmation: requiresConfirmation
        )
    }

    private func evaluateConditions(
        _ conditions: [ConditionRule],
        question: NoemaQuestion,
        runtimeState: RuntimeState
    ) -> Bool {
        // All conditions must be true (AND logic)
        return conditions.allSatisfy { condition in
            evaluateCondition(condition, question: question, runtimeState: runtimeState)
        }
    }

    private func evaluateCondition(
        _ condition: ConditionRule,
        question: NoemaQuestion,
        runtimeState: RuntimeState
    ) -> Bool {
        switch condition.field {
        case "content":
            return evaluateStringCondition(
                condition,
                value: question.content
            )
        case "token_count":
            let tokenCount = estimateTokenCount(question.content)
            return evaluateNumericCondition(
                condition,
                value: tokenCount
            )
        case "intent":
            return question.intent?.rawValue == condition.value
        case "privacy_level":
            return question.privacyLevel.rawValue == condition.value
        default:
            return false
        }
    }
}

struct PolicyEvaluationResult {
    let allowed: Bool
    let appliedConstraints: [UUID]
    let forcedRoute: ExecutionRoute?
    let warnings: [String]
    let requiresConfirmation: String?
}
```

---

## 3.5 Integration with Router

The Policy Engine executes **before** the Router:

```swift
func processQuestion(_ question: NoemaQuestion) async throws -> NoemaResponse {
    let traceId = UUID()

    // Step 1: Policy Evaluation
    let policyResult = try policyEngine.evaluateConstraints(
        question: question,
        runtimeState: runtimeState
    )

    // Step 2: Handle Confirmation Requirement
    if let confirmationPrompt = policyResult.requiresConfirmation {
        let userConfirmed = try await requestUserConfirmation(confirmationPrompt)
        guard userConfirmed else {
            throw ExecutionError.userCancelled
        }
    }

    // Step 3: Apply Forced Route (if any)
    var modifiedQuestion = question
    if let forcedRoute = policyResult.forcedRoute {
        modifiedQuestion.privacyLevel = (forcedRoute == .local) ? .local : .cloud
        logPolicyOverride(constraint: policyResult.appliedConstraints, traceId: traceId)
    }

    // Step 4: Router Decision
    let routingDecision = try router.route(
        question: modifiedQuestion,
        runtimeState: runtimeState
    )

    // Step 5: Execute
    return try await execute(
        question: modifiedQuestion,
        decision: routingDecision,
        traceId: traceId
    )
}
```

---

## 3.6 Determinism Guarantee

The Policy Engine must be deterministic:
- **No machine learning** — All rules are explicit.
- **No probabilistic evaluation** — Conditions are boolean.
- **No external API calls** — All evaluation is local.
- **No time-based conditions** — Constraints do not expire (unless explicitly disabled by user).

---

## 3.7 Constraint Priority and Conflict Resolution

This subsection defines the **exact semantics** of constraint evaluation when multiple constraints apply to a single question, including how conflicts between competing actions are resolved.

### Constraint Priority Model

Each constraint has two priority-related attributes:

```swift
struct Constraint: Codable, Identifiable {
    let id: UUID                // Stable, unique identifier
    let name: String
    let type: ConstraintType
    let enabled: Bool
    let priority: Int           // Lower number = evaluated earlier (1 is highest priority)
    let conditions: [ConditionRule]
    let action: ConstraintAction
}
```

**Priority Semantics:**

- `priority` is an integer where **lower values indicate higher priority** (e.g., `priority: 1` is evaluated before `priority: 2`).
- When multiple constraints have the **same priority**, they are evaluated in **deterministic UUID order** (lexicographical comparison of `id.uuidString`).
- This ensures that evaluation order is **fully deterministic** even when priorities collide.

---

### Constraint Evaluation Order

The Policy Decision Engine evaluates constraints in the following sequence:

```swift
func evaluateConstraints(
    question: NoemaQuestion,
    runtimeState: RuntimeState
) throws -> PolicyEvaluationResult {
    // Step 1: Filter enabled constraints
    let activeConstraints = constraints.filter { $0.enabled }

    // Step 2: Sort by (priority, id) for deterministic ordering
    let sortedConstraints = activeConstraints.sorted { lhs, rhs in
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority  // Lower priority number first
        } else {
            return lhs.id.uuidString < rhs.id.uuidString  // Stable UUID ordering
        }
    }

    // Step 3: Evaluate conditions and collect matching constraints
    var matchedConstraints: [Constraint] = []
    for constraint in sortedConstraints {
        if evaluateConditions(constraint.conditions, question: question, runtimeState: runtimeState) {
            matchedConstraints.append(constraint)
        }
    }

    // Step 4: Apply conflict resolution (Section 3.7.2)
    return resolveConflicts(matchedConstraints: matchedConstraints)
}
```

**Invariants:**

- Constraint evaluation is **deterministic**: Same inputs → same output.
- All enabled constraints are evaluated (no short-circuiting based on first match).
- Conflict resolution happens **after** all condition evaluations are complete.

---

### Constraint Action Precedence

When multiple constraints match a single question, their actions may conflict. The Policy Engine uses a **precedence hierarchy** to resolve conflicts:

```swift
enum ConstraintAction: Codable {
    case block(reason: String)                    // Precedence: 1 (highest)
    case forceLocal                               // Precedence: 2
    case forceCloud                               // Precedence: 3
    case requireConfirmation(prompt: String)      // Precedence: 4
    case warn(message: String)                    // Precedence: 5 (lowest)
}
```

**Precedence Rules:**

1. **BLOCK** (Precedence 1) — Hard stop; execution is prevented entirely.
   - If any constraint returns `block`, the policy evaluation throws `PolicyViolationError`.
   - No routing decision is made; the user sees an error dialog.
   - Example: "Prompt contains sensitive keywords (SSN, credit card)."

2. **FORCE_LOCAL / FORCE_CLOUD** (Precedence 2-3) — Route enforcement.
   - If `forceLocal` and `forceCloud` both match, **forceLocal wins** (privacy-first principle).
   - The enforced route is passed to the Router, which sets `privacyLevel` accordingly.
   - Fallback is **disabled** when a route is forced (`fallbackAllowed = false`).

3. **REQUIRE_CONFIRMATION** (Precedence 4) — User approval required.
   - If present, the UI displays a confirmation dialog before execution proceeds.
   - If user declines, execution is cancelled (equivalent to `BLOCK`).
   - Multiple confirmation prompts are **concatenated** with newline separators.

4. **WARN** (Precedence 5) — Informational only.
   - Displays a non-blocking warning message in the UI.
   - Execution proceeds normally after the warning is shown.
   - Multiple warnings are **aggregated** and displayed together.

---

### Conflict Resolution Algorithm

The `resolveConflicts` function applies the precedence hierarchy:

```swift
func resolveConflicts(matchedConstraints: [Constraint]) throws -> PolicyEvaluationResult {
    var effectiveAction: ConstraintAction? = nil
    var appliedConstraintIds: [UUID] = []
    var warnings: [String] = []
    var confirmationPrompts: [String] = []

    for constraint in matchedConstraints {
        appliedConstraintIds.append(constraint.id)

        switch constraint.action {
        case .block(let reason):
            // BLOCK has highest precedence; throw immediately
            throw PolicyViolationError.blocked(
                reason: reason,
                constraintId: constraint.id,
                appliedConstraints: appliedConstraintIds
            )

        case .forceLocal:
            // Force local unless forceCloud has already been set
            if effectiveAction == nil || effectiveAction == .forceCloud {
                effectiveAction = .forceLocal  // forceLocal wins in conflicts
            }

        case .forceCloud:
            // Force cloud only if no route has been forced yet
            if effectiveAction == nil {
                effectiveAction = .forceCloud
            }
            // If forceLocal was already set, forceLocal wins (no-op here)

        case .requireConfirmation(let prompt):
            confirmationPrompts.append(prompt)

        case .warn(let message):
            warnings.append(message)
        }
    }

    return PolicyEvaluationResult(
        allowed: true,
        effectiveAction: effectiveAction,
        appliedConstraints: appliedConstraintIds,
        warnings: warnings,
        requiresConfirmation: confirmationPrompts.isEmpty ? nil : confirmationPrompts.joined(separator: "\n\n")
    )
}
```

**Updated PolicyEvaluationResult:**

```swift
struct PolicyEvaluationResult {
    let allowed: Bool                       // Always true if no BLOCK action
    let effectiveAction: ConstraintAction?  // Winning action after conflict resolution
    let appliedConstraints: [UUID]          // All matched constraint IDs
    let warnings: [String]                  // Aggregated warning messages
    let requiresConfirmation: String?       // Combined confirmation prompt (if any)
}
```

---

### Conflict Resolution Examples

#### Example 1: BLOCK vs FORCE_LOCAL

```swift
Constraint 1: priority=1, action=.block(reason: "Contains SSN")
Constraint 2: priority=2, action=.forceLocal
```

**Result:** `PolicyViolationError` is thrown. Constraint 1 blocks execution; Constraint 2 is never applied.

---

#### Example 2: FORCE_LOCAL vs FORCE_CLOUD

```swift
Constraint 1: priority=1, action=.forceLocal
Constraint 2: priority=2, action=.forceCloud
```

**Result:** `effectiveAction = .forceLocal`. Privacy-first principle ensures local execution is enforced.

---

#### Example 3: WARN + REQUIRE_CONFIRMATION

```swift
Constraint 1: priority=1, action=.warn(message: "Large query")
Constraint 2: priority=2, action=.requireConfirmation(prompt: "Proceed?")
```

**Result:** Both constraints apply. User sees warning message **and** must confirm before execution.

---

#### Example 4: Multiple Warnings

```swift
Constraint 1: priority=1, action=.warn(message: "Query is long")
Constraint 2: priority=2, action=.warn(message: "Cloud costs may apply")
```

**Result:** Both warnings are displayed together: `["Query is long", "Cloud costs may apply"]`.

---

### Determinism Guarantee for Policy Evaluation

The Policy Engine's conflict resolution is **fully deterministic**:

```swift
// Test: Policy evaluation determinism
let question = NoemaQuestion(/* fixed values */)
let state = RuntimeState(/* fixed values */)

let result1 = policyEngine.evaluateConstraints(question: question, runtimeState: state)
let result2 = policyEngine.evaluateConstraints(question: question, runtimeState: state)

assert(result1.effectiveAction == result2.effectiveAction)
assert(result1.appliedConstraints == result2.appliedConstraints)
assert(result1.warnings == result2.warnings)
assert(result1.requiresConfirmation == result2.requiresConfirmation)
```

This test must pass for all valid inputs. Any non-deterministic behavior violates the design contract.

---

### Integration with Router

The Policy Engine runs **before** the Router. The workflow is:

```
User Input
   ↓
Policy Decision Engine
   ↓
   ├─ If BLOCK → throw error, stop
   ├─ If FORCE_LOCAL/CLOUD → pass to Router as modified question.privacyLevel
   └─ If WARN/CONFIRM → display UI, then continue
   ↓
Router Decision (Section 2)
   ↓
Execution
```

The Router receives the `PolicyEvaluationResult` and applies forced routes as explicit `privacyLevel` overrides (see Section 2.5, Step 1).

---

# SECTION 4 — Constraint Editor

## 4.1 Purpose

The **Constraint Editor** is a UI component that allows users to create, edit, and manage constraints without writing code.

It must:
- Be **user-friendly** (no technical knowledge required).
- Provide **templates** for common constraints.
- Allow **custom constraints** for advanced users.
- Persist constraints **locally** (not synced to cloud by default).
- Enforce **validation** to prevent invalid constraint definitions.

---

## 4.2 UI Design

### Main Constraint List View

```
┌──────────────────────────────────────────────┐
│ Constraints                          [+ New] │
├──────────────────────────────────────────────┤
│                                              │
│ [✓] Block Sensitive Data            [Edit]  │
│     Privacy • Priority: 1                    │
│     Action: Block                            │
│                                              │
│ [✓] Limit Cloud Costs              [Edit]  │
│     Cost • Priority: 2                       │
│     Action: Require Confirmation             │
│                                              │
│ [ ] Force Local for Personal       [Edit]  │
│     Privacy • Priority: 1                    │
│     Action: Force Local (Disabled)           │
│                                              │
└──────────────────────────────────────────────┘
```

---

### Constraint Editor View

```
┌──────────────────────────────────────────────┐
│ Edit Constraint                              │
├──────────────────────────────────────────────┤
│ Name:                                        │
│ [Block Sensitive Data                     ]  │
│                                              │
│ Type:                                        │
│ [Privacy ▼]                                  │
│                                              │
│ Priority: [1   ]                             │
│                                              │
│ Enabled: [✓]                                 │
│                                              │
├──────────────────────────────────────────────┤
│ Conditions (All must be true)                │
├──────────────────────────────────────────────┤
│                                              │
│ Field: [Content ▼]                           │
│ Operator: [Contains ▼]                       │
│ Value: [SSN|credit card|password         ]   │
│                                  [+ Add OR]  │
│                                              │
├──────────────────────────────────────────────┤
│ Action                                       │
├──────────────────────────────────────────────┤
│                                              │
│ [Block Execution ▼]                          │
│                                              │
│ Reason:                                      │
│ [Prompt contains sensitive data           ]  │
│                                              │
├──────────────────────────────────────────────┤
│           [Cancel]          [Save]           │
└──────────────────────────────────────────────┘
```

---

## 4.3 Constraint Templates

Pre-defined templates for common use cases:

### Template 1: Privacy Protection

```yaml
name: "Protect Personal Information"
type: privacy
conditions:
  - field: content
    operator: contains
    value: "SSN|credit card|social security|passport"
action: block
  reason: "This prompt may contain personal information"
```

### Template 2: Cost Control

```yaml
name: "Warn on Large Queries"
type: cost
conditions:
  - field: token_count
    operator: exceeds
    value: 5000
action: warn
  message: "This query is large and may incur cloud costs"
```

### Template 3: Force Local Execution

```yaml
name: "Always Use Local Model"
type: privacy
conditions:
  - field: privacy_level
    operator: equals
    value: "auto"
action: forceLocal
```

### Template 4: Block Specific Topics

```yaml
name: "Block Harmful Content"
type: intent
conditions:
  - field: content
    operator: contains
    value: "violence|illegal|harmful"
action: block
  reason: "This prompt contains restricted keywords"
```

---

## 4.4 Storage and Persistence

Constraints are stored locally using SwiftData or Core Data:

```swift
@Model
class ConstraintEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var type: String
    var enabled: Bool
    var priority: Int
    var conditionsJSON: String  // Serialized JSON
    var actionJSON: String      // Serialized JSON
    var createdAt: Date
    var updatedAt: Date
}
```

### Persistence Rules

1. **Local-only by default** — Constraints are not synced to cloud.
2. **Optional export/import** — Users can export constraints as JSON for backup.
3. **Version compatibility** — Constraint schema must be versioned to handle future changes.

---

## 4.5 Validation Rules

Before saving a constraint, validate:

1. **Name is not empty**
2. **At least one condition is defined**
3. **All condition fields are valid** (e.g., `token_count` requires numeric value)
4. **Priority is unique** (or automatically re-sort on conflict)
5. **Action is properly configured** (e.g., block requires reason)

If validation fails, show inline error messages and prevent save.

---

## 4.6 Human-Readable Constraint Display

In the UI, constraints should be displayed in natural language:

```
✓ Block Sensitive Data
  If prompt contains "SSN" or "credit card" or "password"
  Then block execution with reason: "Prompt contains sensitive data"

✓ Limit Cloud Costs
  If token count exceeds 8000 and privacy level is "auto"
  Then require confirmation: "This query may incur high costs. Continue?"
```

This improves user understanding and reduces configuration errors.

---

# SECTION 5 — Execution Visibility Layer

## 5.1 Purpose

Every execution attempt must be **visible and auditable**.

The Execution Visibility Layer ensures:
1. All routing decisions are logged.
2. All execution attempts are logged.
3. All errors are logged with structured metadata.
4. Users can inspect execution history.
5. Developers can debug issues with `trace_id`.

---

## 5.2 What Must Be Logged

### Routing Decision Log

```swift
struct RoutingLog: Codable {
    let traceId: UUID
    let questionId: UUID
    let sessionId: UUID
    let timestamp: Date
    let privacyLevel: String
    let route: String              // "local" | "cloud"
    let model: String
    let ruleId: String             // Which routing rule was applied
    let fallbackAllowed: Bool
    let appliedConstraints: [UUID] // Which constraints affected this decision
    let tokenCount: Int
}
```

### Execution Log

```swift
struct ExecutionLog: Codable {
    let traceId: UUID
    let questionId: UUID
    let timestamp: Date
    let route: String
    let model: String
    let result: ExecutionResult     // "success" | "error"
    let latencyMs: Int
    let fallbackUsed: Bool
    let errorCode: String?
    let contentHash: String         // SHA256 of prompt (for debugging)
}

enum ExecutionResult: String, Codable {
    case success
    case error
}
```

### Constraint Evaluation Log

```swift
struct ConstraintLog: Codable {
    let traceId: UUID
    let questionId: UUID
    let timestamp: Date
    let evaluatedConstraints: [UUID]
    let appliedConstraints: [UUID]
    let policyViolation: Bool
    let violationReason: String?
}
```

---

## 5.3 UI Display: Execution History

### Compact View

```
┌──────────────────────────────────────────────┐
│ Execution History                            │
├──────────────────────────────────────────────┤
│                                              │
│ 2026-02-21 14:23:45                          │
│ ✓ Local • llama-3.2 • 420ms                 │
│ What is the capital of France?              │
│                                 [Details ▼]  │
│                                              │
│ 2026-02-21 14:18:12                          │
│ ✓ Cloud • gpt-4 • 1.2s • Fallback used      │
│ Analyze this complex dataset...             │
│                                 [Details ▼]  │
│                                              │
│ 2026-02-21 14:05:33                          │
│ ✗ Local • llama-3.2 • Error                 │
│ Generate a 10,000 word essay...             │
│                                 [Details ▼]  │
│                                              │
└──────────────────────────────────────────────┘
```

### Expanded Detail View

```
┌──────────────────────────────────────────────┐
│ Execution Details                            │
├──────────────────────────────────────────────┤
│ Trace ID: a7f3c91e-4b2a-...                  │
│ Question ID: 5d8e2a1f-...                    │
│ Session ID: 9c4f7b3d-...                     │
│                                              │
│ Timestamp: 2026-02-21 14:23:45 UTC           │
│ Route: Local                                 │
│ Model: llama-3.2-8b                          │
│ Token Count: 42                              │
│                                              │
│ Routing Decision:                            │
│ • Rule: AUTO_LOCAL                           │
│ • Reason: Token count within threshold       │
│ • Fallback Allowed: Yes                      │
│                                              │
│ Constraints Applied:                         │
│ • None                                       │
│                                              │
│ Execution:                                   │
│ • Result: Success                            │
│ • Latency: 420ms                             │
│ • Fallback Used: No                          │
│                                              │
│ [Export Log] [Copy Trace ID]                 │
└──────────────────────────────────────────────┘
```

---

## 5.4 Log Storage

### Local Storage (SQLite via SwiftData)

```swift
@Model
class ExecutionLogEntity {
    @Attribute(.unique) var traceId: UUID
    var questionId: UUID
    var sessionId: UUID
    var timestamp: Date
    var route: String
    var model: String
    var result: String
    var latencyMs: Int
    var fallbackUsed: Bool
    var errorCode: String?
    var contentHash: String
    var routingLogJSON: String
    var constraintLogJSON: String
}
```

### Retention Policy

- **Default retention**: 30 days
- **User-configurable**: 7 days to 365 days
- **Manual export**: Users can export logs as JSON before deletion
- **Privacy mode**: Option to disable logging entirely (except errors)

---

## 5.5 trace_id Propagation

The `trace_id` must be propagated across all system boundaries:

1. **Client generates trace_id** when question is created.
2. **Router logs trace_id** with routing decision.
3. **Client sends trace_id** to server in request payload.
4. **Server logs trace_id** for all execution events.
5. **Server returns trace_id** in response payload.
6. **Client displays trace_id** in error messages and detail views.

### Request Payload

```json
{
  "trace_id": "a7f3c91e-4b2a-4d8c-9f1e-3c5b7a8d9e0f",
  "question_id": "5d8e2a1f-8c3b-4f7a-b2d1-9e4a6c8f1b2d",
  "session_id": "9c4f7b3d-2e1a-4c8f-a7b3-1d5e9c2f8a6b",
  "task_type": "cloud_llm",
  "content": "What is the capital of France?",
  "privacy_level": "auto"
}
```

### Response Payload

```json
{
  "trace_id": "a7f3c91e-4b2a-4d8c-9f1e-3c5b7a8d9e0f",
  "question_id": "5d8e2a1f-8c3b-4f7a-b2d1-9e4a6c8f1b2d",
  "status": "success",
  "response": {
    "content": "The capital of France is Paris.",
    "model": "gpt-4",
    "latency_ms": 1240
  }
}
```

---

## 5.6 Error Display with trace_id

When an error occurs, display `trace_id` prominently:

```
┌──────────────────────────────────────────────┐
│ Execution Failed                             │
├──────────────────────────────────────────────┤
│                                              │
│ ⚠️ Local Model Unavailable                   │
│                                              │
│ The local model could not execute this       │
│ query. Please check that the model is        │
│ downloaded and initialized.                  │
│                                              │
│ Error Code: E-LOCAL-001                      │
│ Trace ID: a7f3c91e-4b2a-...                  │
│                                              │
│ [Copy Trace ID] [View Details] [Retry]       │
└──────────────────────────────────────────────┘
```

Users can copy the `trace_id` and provide it to support for debugging.

---

## 5.7 Human Control and Execution Visibility Guarantees

This subsection defines what **"All execution calls visible"** means in concrete terms of UI, user control, and system behavior. Visibility is not merely logging — it is the combination of **human inspectability** and **human control over execution and fallback**.

### Human-Control Invariants

The following invariants must **always** hold in the NoesisNoema client:

#### Invariant 1: Every Execution is Human-Triggered

**Requirement:**

- Every execution attempt MUST be initiated by an **explicit user action**.
- Permitted triggers:
  - Pressing "Send" button in chat interface
  - Pressing "Retry" button in error dialog
  - Invoking execution via keyboard shortcut (e.g., Cmd+Enter)

**Forbidden:**

- Background execution triggered by timers, system events, or daemons
- Automatic re-execution on app resume or network reconnection
- Pre-emptive execution based on predictive text analysis
- Server-initiated execution (push notifications that trigger execution)

**Enforcement:**

- All execution entry points are gated by UI event handlers.
- No background threads may invoke `ExecutionCoordinator.execute()`.
- The app does not register for background fetch or silent push notifications for execution purposes.

---

#### Invariant 2: Fallback Requires User Confirmation

**Requirement:**

Fallback from local → cloud execution is ONLY permitted when **both** of the following conditions are met:

1. `RoutingDecision.fallbackAllowed == true` (determined by Router based on `privacy_level == .auto`)
2. The user has **explicitly confirmed** the fallback via a UI prompt

**Confirmation Prompt Example:**

```
┌──────────────────────────────────────────────┐
│ Local Execution Failed                       │
├──────────────────────────────────────────────┤
│                                              │
│ The local model could not complete this      │
│ request:                                     │
│                                              │
│ Error: Token limit exceeded                  │
│                                              │
│ Would you like to send this query to the     │
│ cloud instead?                               │
│                                              │
│ [Cancel]              [Send to Cloud]        │
└──────────────────────────────────────────────┘
```

**Enforcement:**

- If `fallbackAllowed == false`, no confirmation dialog is shown; the error is displayed immediately.
- If `fallbackAllowed == true` and local execution fails:
  1. Execution is paused.
  2. Confirmation dialog is displayed.
  3. If user clicks "Cancel", execution terminates and error is logged.
  4. If user clicks "Send to Cloud", a new `RoutingDecision` is created with `ruleId: LOCAL_FAILURE_FALLBACK` and cloud execution proceeds.
- The user's choice (confirmed/cancelled) is logged in `ExecutionLog.fallbackConfirmed`.

**Privacy Guarantee:**

- When `privacy_level == .local`, `fallbackAllowed` is **always false**, so no fallback prompt is ever shown.
- This structurally enforces the privacy boundary: local-only execution cannot silently escalate to cloud.

---

#### Invariant 3: No Automatic Retry

**Requirement:**

- If execution fails, the system MUST NOT automatically retry.
- All retries require **explicit user action** (pressing a "Retry" button).

**Forbidden:**

- Exponential backoff retry loops
- Automatic retry on network timeout
- Silent retry with modified routing decision

**Permitted:**

- User presses "Retry" button → same `NoemaQuestion` is re-submitted, triggering a fresh routing decision and execution attempt.
- If the user modifies the prompt or changes settings (e.g., `privacy_level`), this creates a **new** `NoemaQuestion` with a new `question_id`.

**Enforcement:**

- The `ExecutionCoordinator` does not implement retry logic.
- Error handlers in the UI provide a "Retry" button that re-invokes the execution pipeline from the beginning (Policy Engine → Router → Execution).

---

### Connection to UI and Logs

The three invariants above are made visible through the following UI and logging mechanisms:

#### Execution History View

The Execution History UI (Section 5.3) MUST display the following fields for each execution:

- **Timestamp** — When the execution was triggered
- **Route** — Local or Cloud
- **Routing Rule ID** — Which rule determined the route (e.g., `AUTO_LOCAL`, `PRIVACY_LOCAL`)
- **Model** — Which model was used
- **Result** — Success or Error (with error code)
- **Fallback Used** — Boolean indicating whether fallback occurred
- **Fallback Confirmed** — Boolean indicating whether user confirmed fallback (if applicable)
- **Latency** — Execution time in milliseconds
- **Trace ID** — For debugging and support

**Example Display:**

```
┌──────────────────────────────────────────────┐
│ Execution History                            │
├──────────────────────────────────────────────┤
│ 2026-02-21 14:23:45                          │
│ ✓ Local • llama-3.2 • 420ms                 │
│ Rule: AUTO_LOCAL                             │
│ What is the capital of France?              │
│                                 [Details ▼]  │
│                                              │
│ 2026-02-21 14:18:12                          │
│ ✓ Cloud • gpt-4 • 1.2s • Fallback (confirmed)│
│ Rule: LOCAL_FAILURE_FALLBACK                 │
│ Analyze this complex dataset...             │
│                                 [Details ▼]  │
└──────────────────────────────────────────────┘
```

Users can expand "Details" to see:
- Full routing decision (including why fallback was allowed)
- Applied policy constraints (if any)
- Full error message (if execution failed)
- Complete `trace_id`

---

#### Error Dialogs

When an error occurs, the error dialog MUST include:

1. **Human-readable error message** (not raw exception text)
2. **Error code** (e.g., `E-LOCAL-001`)
3. **Trace ID** (truncated for display, full ID copyable)
4. **Action buttons:**
   - "Copy Trace ID" — Copies full `trace_id` to clipboard
   - "View Details" — Opens Execution History and scrolls to this execution
   - "Retry" — Re-submits the same question (creates new execution with new `trace_id`)

**Example Error Dialog:**

```
┌──────────────────────────────────────────────┐
│ Execution Failed                             │
├──────────────────────────────────────────────┤
│                                              │
│ ⚠️ Cloud Service Unavailable                 │
│                                              │
│ The cloud execution service is temporarily   │
│ unavailable. Please try again later or use   │
│ local execution.                             │
│                                              │
│ Error Code: E-CLOUD-002                      │
│ Trace ID: a7f3c91e-4b2a-...                  │
│                                              │
│ [Copy Trace ID] [View Details] [Retry]       │
└──────────────────────────────────────────────┘
```

---

#### Execution Logs

All execution attempts are logged to local storage (Section 5.4) with the following fields:

```swift
struct ExecutionLog: Codable {
    let traceId: UUID
    let questionId: UUID
    let sessionId: UUID
    let timestamp: Date
    let route: String                   // "local" | "cloud"
    let model: String
    let routingRuleId: String           // From RoutingRuleId enum
    let result: ExecutionResult         // "success" | "error"
    let errorCode: String?
    let latencyMs: Int
    let fallbackAllowed: Bool
    let fallbackUsed: Bool
    let fallbackConfirmed: Bool?        // nil if no fallback occurred
    let contentHash: String             // SHA256 of question.content
    let policyConstraintsApplied: [UUID] // IDs of constraints that matched
}
```

These logs enable:
- **Auditability** — Every execution can be traced back to a user action
- **Debugging** — Developers can reconstruct execution flow using `trace_id`
- **Compliance** — Regulatory audits can verify privacy enforcement

---

### Mapping to EPIC 1 Definition of Done

The Definition of Done for EPIC 1 includes the following requirements. This section explicitly maps each DoD item to its implementation in the design:

| DoD Requirement                         | Implementation Reference                          |
|-----------------------------------------|---------------------------------------------------|
| **Routing logic explicit**              | Sections 2.1–2.5 (Routing Decision Inputs, Outputs, Rules, Determinism) |
| **Policy decision engine exists**       | Sections 3.1–3.7 (Policy Model, Evaluation, Conflict Resolution) |
| **Constraint editor implemented**       | Section 4 (Constraint Editor UI, Storage, Templates) |
| **All execution calls visible**         | Sections 5.1–5.7 (Logging, UI, trace_id, Human Control Guarantees) |

**"All execution calls visible" means:**

1. **Every execution is logged** with full metadata (route, model, rule ID, latency, errors).
2. **Logs are inspectable** via Execution History UI.
3. **Trace IDs are propagated** end-to-end (client → server → client).
4. **Errors display trace IDs** for debugging.
5. **Fallback requires user confirmation** (no silent escalation).
6. **No automatic retry** (all retries are user-triggered).
7. **Routing decisions are human-readable** (rule IDs map to descriptions).

This ensures that visibility is not just a logging feature, but a **human sovereignty guarantee**: the user can see, understand, and control all execution behavior.

---

# SECTION 6 — Boundary Compliance Checklist

This section maps each RAGfish design rule to a specific implementation requirement in NoesisNoema.

---

## 6.1 Router Decision Matrix Compliance

| Design Rule | Implementation Requirement | Status |
|------------|---------------------------|--------|
| **Router must execute client-side** | Implement `RouterEngine` as Swift component in client app | ⏳ Pending |
| **Server must not make routing decisions** | Server API only accepts `task_type`, does not analyze prompts | ⏳ Pending |
| **Routing must be deterministic** | Router uses pure functions, no probabilistic logic | ⏳ Pending |
| **privacy_level == "local" prevents network** | Client never sends request if `privacy_level == .local` | ⏳ Pending |
| **Routing decision must be logged** | All routing decisions stored in `RoutingLog` | ⏳ Pending |
| **Fallback only allowed if specified** | `fallbackAllowed` flag controls escalation | ⏳ Pending |
| **No hidden model escalation** | Model selection logged and visible in UI | ⏳ Pending |

---

## 6.2 Invocation Boundary Compliance

| Design Rule | Implementation Requirement | Status |
|------------|---------------------------|--------|
| **Every execution is human-triggered** | No background processing; all execution requires user action | ⏳ Pending |
| **One Question → One Response** | No recursive invocations; execution terminates after response | ⏳ Pending |
| **No autonomous drift** | No self-modifying behavior; no tool self-discovery | ⏳ Pending |
| **Execution must be traceable** | All executions logged with `trace_id` | ⏳ Pending |
| **No hidden side effects** | No implicit memory writes; all state changes logged | ⏳ Pending |

---

## 6.3 Security Model Compliance

| Design Rule | Implementation Requirement | Status |
|------------|---------------------------|--------|
| **Client is trusted by user** | Session memory stored locally; server is mirror only | ⏳ Pending |
| **TLS required for cloud** | Network layer enforces HTTPS; no plaintext transport | ⏳ Pending |
| **session_id treated as secret** | session_id stored securely; not logged in plaintext | ⏳ Pending |
| **privacy_level == "local" guarantees zero network** | Structural enforcement: request never constructed | ⏳ Pending |
| **Session timeout = 45 minutes** | Client enforces timeout; server purges expired sessions | ⏳ Pending |
| **No background execution** | All execution visible and logged | ⏳ Pending |

---

## 6.4 Execution Flow Compliance

| Design Rule | Implementation Requirement | Status |
|------------|---------------------------|--------|
| **Human input is origin** | User action creates `NoemaQuestion` | ⏳ Pending |
| **Router validates before execution** | Policy Engine and Router run before network call | ⏳ Pending |
| **Privacy enforced before network** | Privacy check blocks request if `privacy_level == .local` | ⏳ Pending |
| **No hidden autonomy** | All execution paths logged and visible | ⏳ Pending |
| **Session memory scoped to client** | Memory stored locally, mirrored to server for 45 minutes | ⏳ Pending |

---

## 6.5 Observability Standard Compliance

| Design Rule | Implementation Requirement | Status |
|------------|---------------------------|--------|
| **trace_id propagated end-to-end** | Client generates; server returns; errors display | ⏳ Pending |
| **All routing logged** | `RoutingLog` captures every decision | ⏳ Pending |
| **All execution logged** | `ExecutionLog` captures every attempt | ⏳ Pending |
| **Logs are user-inspectable** | Execution History UI displays logs | ⏳ Pending |
| **Production logs avoid raw prompts** | Only `content_hash` stored; no plaintext content | ⏳ Pending |
| **Logs do not trigger autonomy** | Logs are passive records only | ⏳ Pending |

---

## 6.6 Error Doctrine Compliance

| Design Rule | Implementation Requirement | Status |
|------------|---------------------------|--------|
| **Fail explicitly** | All errors return structured `StructuredError` | ⏳ Pending |
| **No silent recovery** | No hidden retries except explicit network retry | ⏳ Pending |
| **Errors are typed** | Use enum `ErrorCode` with stable identifiers | ⏳ Pending |
| **Errors include trace_id** | All errors display `trace_id` for debugging | ⏳ Pending |
| **Fallback only if allowed** | `fallbackAllowed` flag controls escalation | ⏳ Pending |
| **No autonomous retry** | Retry requires user action | ⏳ Pending |

---

# APPENDIX A — Swift Component Architecture

## High-Level Component Diagram

```
┌─────────────────────────────────────────────────────────┐
│                      User Interface                      │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────┐ │
│  │ Chat View  │  │ Constraint │  │ Execution History  │ │
│  │            │  │ Editor     │  │ View               │ │
│  └────────────┘  └────────────┘  └────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                  Presentation Layer                      │
│  ┌────────────────────────────────────────────────────┐ │
│  │            QuestionViewModel                       │ │
│  │  • Creates NoemaQuestion from user input           │ │
│  │  • Triggers policy evaluation                      │ │
│  │  • Triggers routing decision                       │ │
│  │  • Invokes execution                               │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                   Business Logic Layer                   │
│  ┌──────────────────┐  ┌───────────────────────────┐    │
│  │ Policy Engine    │  │ Router Engine             │    │
│  │ • Evaluate       │  │ • Deterministic routing   │    │
│  │   constraints    │  │ • Model selection         │    │
│  │ • Force routes   │  │ • Fallback logic          │    │
│  │ • Block/warn     │  │                           │    │
│  └──────────────────┘  └───────────────────────────┘    │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │            Execution Coordinator                   │ │
│  │  • Invokes local or cloud execution                │ │
│  │  • Handles fallback                                │ │
│  │  • Logs execution                                  │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                   Execution Layer                        │
│  ┌──────────────────┐  ┌───────────────────────────┐    │
│  │ Local Executor   │  │ Cloud Executor            │    │
│  │ • Invoke local   │  │ • HTTP client             │    │
│  │   LLM            │  │ • TLS enforcement         │    │
│  │ • Stream output  │  │ • Timeout handling        │    │
│  └──────────────────┘  └───────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                   Persistence Layer                      │
│  ┌──────────────────┐  ┌───────────────────────────┐    │
│  │ SwiftData Models │  │ Logging Store             │    │
│  │ • Constraints    │  │ • RoutingLog              │    │
│  │ • Sessions       │  │ • ExecutionLog            │    │
│  │                  │  │ • ConstraintLog           │    │
│  └──────────────────┘  └───────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

---

## Component Responsibilities

### QuestionViewModel
- Receives user input
- Creates `NoemaQuestion` object
- Coordinates policy evaluation → routing → execution pipeline
- Updates UI with results

### PolicyDecisionEngine
- Evaluates user-defined constraints
- Blocks/warns/forces routes based on rules
- Returns `PolicyEvaluationResult`

### RouterEngine
- Implements deterministic routing rules
- Produces `RoutingDecision`
- Never performs hidden model selection

### ExecutionCoordinator
- Invokes local or cloud execution based on routing decision
- Handles fallback if allowed
- Logs all execution attempts

### LocalExecutor
- Interfaces with on-device LLM (e.g., llama.cpp)
- Streams output
- Handles local model errors

### CloudExecutor
- Sends HTTP requests to noema-agent server
- Enforces TLS
- Propagates `trace_id`

### LoggingStore
- Persists routing, execution, and constraint logs
- Enforces retention policy
- Provides query interface for Execution History UI

---

# APPENDIX B — Implementation Phases

This design will be implemented in **multiple phases**:

## Phase 1: Router Engine (Week 1-2)
- Implement deterministic routing rules
- Token estimation
- Local model capability checking
- Routing decision logging

## Phase 2: Policy Engine (Week 3-4)
- Constraint model and evaluation algorithm
- Constraint storage (SwiftData)
- Integration with Router

## Phase 3: Constraint Editor UI (Week 5-6)
- Constraint list view
- Constraint editor form
- Template library
- Validation logic

## Phase 4: Execution Visibility (Week 7-8)
- Execution logging infrastructure
- Execution History UI
- trace_id propagation
- Error display with trace_id

## Phase 5: Integration Testing (Week 9-10)
- End-to-end testing of routing pipeline
- Privacy enforcement validation
- Constraint evaluation testing
- UI/UX refinement

---

# APPENDIX C — Open Questions

The following questions must be resolved before implementation:

1. **Local Model Integration**
   - Which local LLM framework will be used? (llama.cpp, CoreML, MLX?)
   - How will model downloads be managed?
   - What is the token threshold for local execution?

2. **Server API Contract**
   - What is the exact schema for `task_type` field?
   - Does the server return `trace_id` in all responses?
   - What error codes does the server return?

3. **Constraint Syntax**
   - Should we support regex patterns in constraint conditions?
   - Should we support OR logic between conditions (currently only AND)?

4. **Log Retention**
   - Should logs be exportable to external systems?
   - Should there be a "privacy mode" that disables all logging?

5. **Performance**
   - What is the acceptable latency for policy evaluation?
   - Should constraint evaluation be parallelized?

---

# APPENDIX D — References

## RAGfish Core Design Documents
- `router-decision-matrix.md` — Deterministic routing specification
- `invocation-boundary.md` — Execution scope and lifecycle
- `security-model.md` — Trust boundaries and threat model
- `execution-flow.md` — End-to-end execution pipeline
- `observability-standard.md` — Logging and traceability requirements
- `error-doctrine.md` — Error classification and handling

## Related NoesisNoema Documents
- ADR-0000: Human Sovereignty Principle
- Session Management Design
- Memory Lifecycle Specification

---

# CONCLUSION

This design document establishes a **comprehensive blueprint** for implementing Client Authority Hardening in NoesisNoema.

The core principles are:
1. **Client owns all routing decisions** — Server is a stateless execution engine.
2. **Routing is deterministic** — No hidden model selection or probabilistic behavior.
3. **Policy enforcement happens client-side** — User constraints are evaluated before execution.
4. **All execution is visible** — Every decision, execution, and error is logged and inspectable.
5. **Privacy is structurally enforced** — `privacy_level == "local"` guarantees zero network transmission.

**This revision clarifies:**

- **Deterministic routing** — Section 2.5 formalizes the Router as a pure function with strict, ordered evaluation rules. All routing decisions are traceable via `RoutingRuleId` and produce identical outputs for identical inputs.

- **Policy conflict resolution** — Section 3.7 defines exact precedence semantics for conflicting constraint actions (BLOCK > FORCE_LOCAL > FORCE_CLOUD > REQUIRE_CONFIRMATION > WARN), ensuring deterministic policy evaluation.

- **Human-visible, human-controlled execution** — Section 5.7 establishes three invariants: (1) every execution is user-triggered, (2) fallback requires user confirmation, (3) no automatic retry. Visibility means inspectability **and** control.

**Next Steps:**
1. Review this design with the team.
2. Resolve open questions (Appendix C).
3. Create implementation tickets for each phase (Appendix B).
4. Begin Phase 1 (Router Engine) implementation.

---

**End of Document**
