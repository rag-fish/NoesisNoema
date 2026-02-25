# EPIC1 Phase4 — Constraint Editor Design

**Project**: NoesisNoema (Swift Client App)
**EPIC**: EPIC1 — Client Authority Hardening
**Phase**: Phase 4 — Constraint Editor
**Document Status**: Implementation-Ready Design
**Created**: 2026-02-24
**Author**: System Architecture Team

---

## Document Purpose

This document defines the architecture and implementation strategy for the **Constraint Editor** — a developer-facing tool for creating, editing, testing, and debugging policy constraints within the NoesisNoema client.

This is a **pre-implementation design document** for Phase 4 of EPIC1. No code will be written until this design is reviewed and approved.

---

# SECTION 1 — Purpose and Scope

## 1.1 Why the Constraint Editor Exists

The Constraint Editor serves three critical functions in support of Client Authority Hardening:

### 1. Human-Controllable Policy Configuration

**Problem:**
Policy constraints defined in `PolicyRule` are currently created programmatically or hardcoded. There is no user interface for creating, editing, or managing these rules.

**Solution:**
The Constraint Editor provides a **visual interface** for defining policy rules, allowing developers (and eventually end-users) to:
- Create new policy constraints without writing code
- Edit existing constraints
- Enable/disable constraints dynamically
- Test constraint behavior before deploying them

**Benefit:**
Users can exercise fine-grained control over privacy, cost, and performance boundaries without requiring code changes or app recompilation.

---

### 2. Determinism Validation and Debugging

**Problem:**
The Policy Engine is a pure function that produces deterministic results, but there is no tool to:
- Verify that constraints produce expected outcomes
- Test conflict resolution behavior
- Debug why a particular constraint triggered or didn't trigger
- Inspect the order of evaluation and precedence resolution

**Solution:**
The Constraint Editor includes a **Simulation Mode** that allows developers to:
- Input test questions and runtime states
- Execute `PolicyEngine.evaluate()` in isolation
- View the effective action, triggered rule IDs, and conflict resolution results
- Verify determinism by running the same inputs multiple times

**Benefit:**
Developers can validate policy behavior before production deployment, reducing the risk of unintended blocking or routing decisions.

---

### 3. Design Compliance Enforcement

**Problem:**
Policy constraints are a key component of Client Authority Hardening (Section 3 of EPIC1 design doc). Without a UI to visualize and test them, it's difficult to ensure that:
- Constraints are correctly prioritized
- Conflict resolution follows the precedence hierarchy (BLOCK > FORCE_LOCAL > FORCE_CLOUD > REQUIRE_CONFIRMATION > WARN)
- Determinism is maintained

**Solution:**
The Constraint Editor enforces design compliance by:
- Validating constraint structure (all fields required)
- Ensuring priority values are unique or explicitly handled
- Displaying human-readable conflict resolution results
- Providing clear feedback when constraints are malformed

**Benefit:**
The UI serves as a **design enforcement layer**, preventing invalid configurations from being saved or deployed.

---

## 1.2 How It Supports Client Authority Hardening

Client Authority Hardening (EPIC1) is built on three pillars:

1. **Deterministic Routing** — Router makes explicit, traceable decisions (Section 2)
2. **Policy Constraints** — User-defined rules override default routing (Section 3)
3. **Execution Visibility** — All decisions are logged and auditable (Section 5)

The Constraint Editor directly supports **Pillar #2** by:
- Making policy configuration accessible to non-programmers
- Providing immediate feedback on policy behavior
- Ensuring that policy constraints are deterministic and testable

Without the Constraint Editor, policy constraints remain a developer-only feature, limiting the **human sovereignty** goal of EPIC1.

---

## 1.3 Relationship to PolicyEngine and Router

### PolicyEngine (Pure Function)

The PolicyEngine (`Shared/Policy/PolicyEngine.swift`) is a **pure, deterministic function**:
- **Input:** `NoemaQuestion`, `RuntimeState`, `[PolicyRule]`
- **Output:** `PolicyEvaluationResult` (effective action, triggered constraints, warnings)
- **Purity Contract:** No I/O, no logging, no global state, no time-based logic

**Relationship to Constraint Editor:**
- The Constraint Editor **does not modify** the PolicyEngine
- The Constraint Editor **calls** `PolicyEngine.evaluate()` in Simulation Mode
- The PolicyEngine remains **pure and deterministic** regardless of UI state

---

### Router (Pure Function)

The Router (`Shared/Routing/Router.swift`) is a **pure, deterministic function**:
- **Input:** `NoemaQuestion`, `RuntimeState`, `PolicyEvaluationResult`
- **Output:** `RoutingDecision` (route target, model, rule ID, fallback allowed)
- **Purity Contract:** No I/O, no logging, no global state

**Relationship to Constraint Editor:**
- The Constraint Editor **does not modify** the Router
- The Constraint Editor tests policy constraints **before** they reach the Router
- The Router receives `PolicyEvaluationResult` from the PolicyEngine (not from the UI)

---

### Data Flow

```
┌────────────────────────────────────────────────────────────┐
│            Constraint Editor (UI Layer)                     │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  User creates/edits PolicyRule                       │  │
│  │  ↓                                                    │  │
│  │  Constraint saved to storage                         │  │
│  │  ↓                                                    │  │
│  │  User triggers Simulation Mode                       │  │
│  │  ↓                                                    │  │
│  │  PolicyEngine.evaluate(question, state, rules)       │  │
│  │  ↓                                                    │  │
│  │  Display: effectiveAction, triggeredRules, warnings  │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
                           │
                           │ (At runtime, production flow)
                           ▼
┌────────────────────────────────────────────────────────────┐
│            Application Execution Flow                       │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  User submits question                               │  │
│  │  ↓                                                    │  │
│  │  Load PolicyRules from storage                       │  │
│  │  ↓                                                    │  │
│  │  PolicyEngine.evaluate(question, state, rules)       │  │
│  │  ↓                                                    │  │
│  │  Router.route(question, state, policyResult)         │  │
│  │  ↓                                                    │  │
│  │  ExecutionCoordinator.execute(decision)              │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

**Key Principle:**
The Constraint Editor is a **development and debugging tool** that operates on the same data structures (`PolicyRule`) used in production, but in a **sandboxed environment** where policy evaluation does not trigger actual execution.

---

## 1.4 Scope for EPIC1 Phase4

### What IS Included

1. **Developer-Facing UI** (macOS only)
   - Constraint list view
   - Constraint editor form
   - Simulation mode for testing
   - Validation and error feedback

2. **Persistence Strategy**
   - JSON-based storage in Application Support directory
   - Load constraints on app startup
   - Save constraints on edit

3. **PolicyRule CRUD Operations**
   - Create new constraint
   - Edit existing constraint
   - Delete constraint
   - Enable/disable constraint

4. **Simulation Mode**
   - Input test question and runtime state
   - Execute `PolicyEngine.evaluate()`
   - Display effective action and triggered rules
   - Verify determinism (run multiple times)

5. **Design Compliance**
   - Validate constraint structure
   - Enforce priority ordering
   - Display conflict resolution results
   - Prevent invalid configurations

---

### What IS NOT Included (Future Phases)

1. **End-User UI** (iOS, iPadOS)
   - Phase 4 is developer-focused (macOS only)
   - End-user constraint editing deferred to Phase 5+

2. **Constraint Templates Library**
   - Pre-defined templates (e.g., "Block Sensitive Data")
   - Deferred to Phase 5 (UI polish)

3. **Execution History Integration**
   - Viewing triggered constraints in past executions
   - Trace ID surfacing
   - Deferred to Phase 5 (Execution Visibility Layer)

4. **Advanced Condition Operators**
   - Regular expressions in condition values
   - OR logic between conditions (currently only AND)
   - Deferred to Phase 6+

5. **Constraint Import/Export**
   - Sharing constraints between devices
   - Cloud sync
   - Deferred to Phase 6+

6. **Performance Monitoring**
   - Measuring policy evaluation latency
   - Profiling constraint matching
   - Deferred to Phase 7+

---

## 1.5 Success Criteria for Phase 4

Phase 4 is considered **complete** when the following criteria are met:

1. **Functional Completeness**
   - [ ] Developer can create a new constraint via UI
   - [ ] Developer can edit an existing constraint
   - [ ] Developer can enable/disable constraints
   - [ ] Developer can delete constraints
   - [ ] Constraints are persisted to disk
   - [ ] Constraints are loaded on app startup

2. **Simulation Mode**
   - [ ] Developer can input a test question
   - [ ] Developer can input a test runtime state
   - [ ] Developer can execute `PolicyEngine.evaluate()`
   - [ ] Results display: effective action, triggered rule IDs, warnings
   - [ ] Determinism is verifiable (same inputs → same outputs)

3. **Design Compliance**
   - [ ] Validation prevents saving malformed constraints
   - [ ] Conflict resolution precedence is displayed correctly
   - [ ] PolicyEngine remains pure (no UI dependencies)
   - [ ] Router is not modified

4. **Testing**
   - [ ] Unit tests for EditablePolicyRule ↔ PolicyRule mapping
   - [ ] Unit tests for constraint persistence
   - [ ] UI tests for constraint CRUD operations
   - [ ] UI tests for simulation mode

5. **Documentation**
   - [ ] Inline code documentation
   - [ ] README for constraint JSON schema
   - [ ] Example constraints included

---

# SECTION 1A — Phase4 MVP Scope Lock

## 1A.1 Purpose of This Section

**Context:** The original design document (Sections 1-9) describes the full vision for the Constraint Editor, including features like template libraries, advanced operators, and execution history integration.

**Problem:** Phase 4 must deliver a **strict MVP** that validates core architecture without scope creep.

**This section defines:**
1. **Exactly what will be implemented** in Phase 4 (minimal viable product)
2. **Exactly what is deferred** to Phase 5+
3. **Simplified architecture** for MVP implementation
4. **Explicit guarantees** about what is NOT changed (Router, PolicyEngine)

---

## 1A.2 What WILL Be Implemented in Phase4

### Core Functionality (Non-Negotiable)

1. **ConstraintStore (Persistence Layer)**
   - Read `[PolicyRule]` from JSON file in Application Support directory
   - Write `[PolicyRule]` to JSON file
   - Location: `~/Library/Application Support/NoesisNoema/policy-constraints.json`
   - **No caching, no validation in store** — just read/write

2. **EditablePolicyRule Model (Domain Layer)**
   - Mutable wrapper around immutable `PolicyRule`
   - Properties: `id`, `name`, `type`, `enabled`, `priority`, `conditions`, `action`
   - Converters: `toPolicyRule()` and `init(from: PolicyRule)`
   - **No template system** — constraints created from scratch

3. **ConstraintEditorViewModel (Business Logic)**
   - Load constraints from `ConstraintStore` on init
   - Save constraints to `ConstraintStore` on save
   - CRUD operations: `addConstraint()`, `deleteConstraint()`, `toggleConstraint()`
   - **Basic validation only:**
     - Name cannot be empty
     - At least one condition required
     - Action-specific validation (e.g., block requires reason)
   - **No priority conflict detection** (deferred to Phase 5)

4. **ConstraintEditorView (UI Layer)**
   - **Simple list view** with constraints displayed as rows
   - Each row shows: checkbox (enable/disable), name, priority, type
   - **No master-detail** — edit in modal sheet
   - **No simulation mode** — deferred to Phase 5
   - Buttons: `[+ New]`, `[Edit]`, `[Delete]`

5. **ConstraintDetailView (Edit Form)**
   - Modal sheet with form fields:
     - Name (TextField)
     - Type (Picker: privacy, cost, performance, intent)
     - Priority (TextField with number formatter)
     - Enabled (Toggle)
     - Conditions (List with Add/Remove)
     - Action (Picker with conditional fields)
   - Save/Cancel buttons
   - **Validation errors displayed inline** (red text below field)

6. **Integration with Production Flow**
   - Define `PolicyRulesProvider` protocol for dependency injection
   - ConstraintEditor updates `PolicyRulesStore` (concrete implementation)
   - ExecutionCoordinator receives rules via initializer injection
   - **No global mutable state (no AppSettings.shared pattern)**
   - **No Router modification**
   - **No PolicyEngine modification**

---

### Minimal JSON Schema (Phase 4)

```json
[
  {
    "id": "uuid-string",
    "name": "Constraint Name",
    "type": "privacy",
    "enabled": true,
    "priority": 1,
    "conditions": [
      {
        "field": "content",
        "operator": "contains",
        "value": "SSN|password"
      }
    ],
    "action": {
      "type": "block",
      "reason": "Contains sensitive data"
    }
  }
]
```

**Action Types (Phase 4):**
- `"block"` (requires `reason`)
- `"forceLocal"` (no additional fields)
- `"forceCloud"` (no additional fields)
- `"requireConfirmation"` (requires `prompt`)
- `"warn"` (requires `message`)

**Condition Operators (Phase 4):**
- `"contains"`, `"notContains"`, `"equals"`, `"notEquals"`, `"exceeds"`, `"lessThan"`

**Condition Fields (Phase 4):**
- `"content"`, `"token_count"`, `"intent"`, `"privacy_level"`

---

### Dependency Injection Pattern (Phase 4)

To avoid global mutable state, Phase 4 uses **dependency injection** for policy rules.

#### PolicyRulesProvider Protocol

```swift
/// Protocol for providing policy rules to execution components
protocol PolicyRulesProvider {
    /// Returns the current set of policy rules
    func getPolicyRules() -> [PolicyRule]
}
```

#### PolicyRulesStore Implementation

```swift
/// Concrete implementation that loads rules from ConstraintStore
class PolicyRulesStore: PolicyRulesProvider {
    private let constraintStore: ConstraintStore
    private var cachedRules: [PolicyRule] = []

    init(constraintStore: ConstraintStore = ConstraintStore.shared) {
        self.constraintStore = constraintStore
        self.loadRules()
    }

    /// Load rules once at initialization
    private func loadRules() {
        do {
            self.cachedRules = try constraintStore.load()
        } catch {
            // Error handling defined in Section 1A.2.1
            print("Failed to load policy rules: \(error)")
            self.cachedRules = []
        }
    }

    func getPolicyRules() -> [PolicyRule] {
        return cachedRules
    }

    /// Called by ConstraintEditor after saving new rules
    /// Does NOT reload automatically - requires app restart
    func notifyRulesUpdated() {
        // In Phase 4: no-op (requires app restart)
        // In Phase 5: could trigger reload
    }
}
```

#### ExecutionCoordinator Integration

```swift
class ExecutionCoordinator {
    private let policyRulesProvider: PolicyRulesProvider

    init(policyRulesProvider: PolicyRulesProvider) {
        self.policyRulesProvider = policyRulesProvider
    }

    func execute(question: NoemaQuestion, runtimeState: RuntimeState) async throws -> NoemaResponse {
        // Get rules via dependency injection
        let rules = policyRulesProvider.getPolicyRules()

        // Policy evaluation
        let policyResult = try PolicyEngine.evaluate(
            question: question,
            runtimeState: runtimeState,
            rules: rules  // ← Injected here
        )

        // Router invocation
        let routingDecision = try Router.route(
            question: question,
            runtimeState: runtimeState,
            policyResult: policyResult
        )

        // ... execution logic
    }
}
```

#### App Initialization

```swift
@main
struct NoesisNoemaApp: App {
    // Initialize PolicyRulesStore once at app startup
    private let policyRulesStore = PolicyRulesStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(policyRulesStore)  // For ConstraintEditor
        }
    }
}
```

**Key Guarantees:**
1. **No global mutable state** — `PolicyRulesStore` is instantiated once in app initialization
2. **Dependency injection** — `ExecutionCoordinator` receives provider via initializer
3. **Immutable after load** — Rules loaded once at startup, not modified during runtime
4. **ConstraintEditor decoupled** — Editor updates JSON file, does not mutate runtime state

---

### Persistence Error Handling (Phase 4)

#### Error Scenarios and Behavior

**Scenario 1: JSON file does not exist**
```swift
func load() throws -> [PolicyRule] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        // Return empty array (no error thrown)
        return []
    }
    // ... continue loading
}
```
**Behavior:** Return empty array. This is expected on first app launch.

---

**Scenario 2: JSON decoding fails (malformed file)**
```swift
func load() throws -> [PolicyRule] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        return []
    }

    let data = try Data(contentsOf: fileURL)

    do {
        let decoder = JSONDecoder()
        return try decoder.decode([PolicyRule].self, from: data)
    } catch {
        // Decoding failed - return empty array but propagate error for logging
        print("⚠️ Failed to decode policy rules: \(error)")
        return []  // Graceful degradation
    }
}
```
**Behavior:** Return empty array AND log error. App continues without constraints.

---

**Scenario 3: File I/O error (permissions, disk full)**
```swift
func save(_ rules: [PolicyRule]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(rules)

    do {
        try data.write(to: fileURL, options: .atomic)
    } catch {
        // Surface error to UI
        throw ConstraintStoreError.writeFailed(underlyingError: error)
    }
}

enum ConstraintStoreError: Error, LocalizedError {
    case writeFailed(underlyingError: Error)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let error):
            return "Failed to save constraints: \(error.localizedDescription)"
        }
    }
}
```
**Behavior:** Throw error. ConstraintEditorViewModel catches and displays to user.

---

**UI Error Display:**
```swift
// In ConstraintEditorViewModel
func saveConstraints() {
    isSaving = true
    saveError = nil

    // ... validation

    do {
        try constraintStore.save(policyRules)
        isSaving = false
    } catch {
        saveError = error  // Display in UI
        isSaving = false
    }
}
```

**In ConstraintEditorView:**
```swift
if let error = viewModel.saveError {
    Text("⚠️ \(error.localizedDescription)")
        .foregroundColor(.red)
}
```

**Critical Guarantee:** **No crashes allowed.** All file I/O errors are caught and handled gracefully.

---

### Loading Lifecycle (Phase 4)

#### Startup Sequence

```
1. App Launch
   ↓
2. PolicyRulesStore.init()
   ↓
3. PolicyRulesStore.loadRules()
   ├─ If file exists → decode and cache
   └─ If file missing or decode fails → cache empty array
   ↓
4. PolicyRulesStore.cachedRules = [...]
   ↓
5. ExecutionCoordinator.init(policyRulesProvider: policyRulesStore)
   ↓
6. App Ready
```

#### Runtime Behavior

**During app session:**
- `cachedRules` remains **immutable**
- `getPolicyRules()` returns **same array** every time
- ConstraintEditor can **edit JSON file** but changes **do not affect runtime**

**After editing constraints:**
```
User edits constraint
  ↓
ConstraintEditorViewModel.saveConstraints()
  ↓
ConstraintStore.save([PolicyRule])
  ↓
Write to policy-constraints.json
  ↓
PolicyRulesStore.notifyRulesUpdated()  // No-op in Phase 4
  ↓
User sees: "✅ Constraints saved. Restart app to apply changes."
```

**Phase 4 Limitation:** **Restart required** to apply constraint changes in production execution.

**Phase 5 Enhancement:** Hot reload — `notifyRulesUpdated()` reloads `cachedRules` and notifies observers.

---

### No Global Mutable State Guarantee

**Prohibited Pattern (NOT used in Phase 4):**
```swift
// ❌ WRONG: Global mutable singleton
class AppSettings {
    static let shared = AppSettings()
    var policyRules: [PolicyRule] = []  // Mutable global state

    func updateRules(_ rules: [PolicyRule]) {
        self.policyRules = rules  // Global mutation
    }
}
```

**Correct Pattern (Phase 4):**
```swift
// ✅ CORRECT: Dependency injection with immutable state
class PolicyRulesStore: PolicyRulesProvider {
    private var cachedRules: [PolicyRule] = []  // Private, loaded once

    init(constraintStore: ConstraintStore) {
        self.cachedRules = /* load once */
    }

    func getPolicyRules() -> [PolicyRule] {
        return cachedRules  // Immutable view
    }
}

// Injected into ExecutionCoordinator (not accessed globally)
let coordinator = ExecutionCoordinator(policyRulesProvider: policyRulesStore)
```

**Guarantees:**
1. `PolicyRulesStore` is instantiated **once** at app startup
2. `cachedRules` is loaded **once** in `init()`
3. `cachedRules` is **never mutated** after initialization (in Phase 4)
4. No component can access rules via global state (must receive via dependency injection)

**Verification:**
- `grep -r "AppSettings.shared" Shared/Policy` → no matches
- `grep -r "\.shared" Shared/Policy` → only `ConstraintStore.shared` (file I/O utility)

---

## 1A.3 What Is DEFERRED to Phase5+

### Explicitly Out of Scope for Phase 4

1. **Simulation Mode**
   - Input test questions and runtime states
   - Execute `PolicyEngine.evaluate()` in isolation
   - Display results and verify determinism
   - **Reason for deferral:** Complex UI, not required for MVP validation

2. **Master-Detail Layout**
   - Split view with constraint list on left, editor on right
   - **Reason for deferral:** Simplified to modal sheet for MVP

3. **Constraint Templates Library**
   - Pre-defined templates (e.g., "Block Sensitive Data")
   - Template picker UI
   - **Reason for deferral:** Nice-to-have, not core functionality

4. **Priority Conflict Detection**
   - Warn when two constraints have same priority
   - Auto-increment priority on add
   - **Reason for deferral:** Determinism is still guaranteed by UUID ordering

5. **Advanced Validation**
   - Regex pattern validation in condition values
   - Dependency checking between constraints
   - **Reason for deferral:** Basic validation is sufficient for MVP

6. **Execution History Integration**
   - Display which constraints triggered in past executions
   - Link constraints to trace IDs
   - **Reason for deferral:** Requires ExecutionCoordinator changes (Phase 5)

7. **Real-Time Constraint Reload**
   - File system watcher to detect external changes
   - Auto-reload when JSON is modified
   - **Reason for deferral:** Manual reload is sufficient for MVP

8. **Constraint Import/Export**
   - Export constraints as JSON file
   - Import constraints from file
   - **Reason for deferral:** Advanced feature, not required for testing

9. **Constraint Provenance Tracking**
   - `createdAt`, `modifiedAt`, `createdBy` fields
   - Audit trail for compliance
   - **Reason for deferral:** Not required for MVP validation

10. **OR Logic Between Conditions**
    - Currently only AND logic is supported
    - OR logic requires PolicyEngine changes
    - **Reason for deferral:** PolicyEngine is unchanged in Phase 4

---

## 1A.4 Simplified Architecture Diagram (MVP)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Phase 4 MVP Architecture                      │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         View Layer (SwiftUI)                     │
│  ┌────────────────────────┐    ┌─────────────────────────────┐  │
│  │ ConstraintEditorView   │───▶│ ConstraintDetailView        │  │
│  │ (List with +/Edit/Del) │    │ (Modal Sheet)               │  │
│  └────────────┬───────────┘    └─────────────────────────────┘  │
└───────────────┼──────────────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     ViewModel Layer                              │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ ConstraintEditorViewModel                                │   │
│  │ • constraints: [EditablePolicyRule]                      │   │
│  │ • loadConstraints()                                      │   │
│  │ • saveConstraints()                                      │   │
│  │ • addConstraint()                                        │   │
│  │ • deleteConstraint(id:)                                  │   │
│  │ • toggleConstraint(id:)                                  │   │
│  │ • validateAll() -> [ValidationError]                     │   │
│  └────────────────────┬─────────────────────────────────────┘   │
└─────────────────────────┼────────────────────────────────────────┘
                          │
         ┌────────────────┼────────────────┐
         │                │                │
         ▼                ▼                ▼
┌─────────────────┐  ┌────────────┐  ┌────────────────────────┐
│ Domain Model    │  │ Pure       │  │ Dependency Injection   │
│                 │  │ Functions  │  │                        │
│ EditablePolicyRule  │ PolicyEngine  │ PolicyRulesProvider    │
│ (mutable)       │  │ (unchanged)│  │ (protocol)             │
│   ↕             │  │            │  │   ↓                    │
│ PolicyRule      │  │ Router     │  │ PolicyRulesStore       │
│ (immutable)     │  │ (unchanged)│  │ (loaded once at init)  │
│                 │  │            │  │   ↓                    │
│                 │  │            │  │ ConstraintStore        │
│                 │  │            │  │ • load() -> [Policy..] │
│                 │  │            │  │ • save([Policy...])    │
│                 │  │            │  │ (JSON file I/O)        │
└─────────────────┘  └────────────┘  └────────────────────────┘
                          ▲
                          │ Injected via protocol
                          │
                    ┌─────┴─────────────────────┐
                    │ ExecutionCoordinator      │
                    │ (receives PolicyRules     │
                    │  via dependency injection)│
                    └───────────────────────────┘
```

**Key Architectural Principles:**
- No `SimulationViewModel` (deferred to Phase 5)
- No `SimulationView` (deferred to Phase 5)
- No template system (deferred to Phase 5)
- No execution history integration (deferred to Phase 5)
- **No global mutable state** (dependency injection via `PolicyRulesProvider`)
- **Immutable after load** (rules loaded once at app startup)

---

## 1A.5 Minimal SwiftUI View Hierarchy

```
ConstraintEditorView (List)
│
├─ ForEach(constraints) { constraint in
│   ConstraintRow(constraint)
│   ├─ Toggle (enabled)
│   ├─ Text (name)
│   ├─ Text (priority)
│   ├─ Badge (type: privacy/cost/performance/intent)
│   ├─ Button("Edit") → .sheet(ConstraintDetailView)
│   └─ Button("Delete") → deleteConstraint()
│  }
│
└─ Button("+ New") → addConstraint()
```

**ConstraintDetailView (Modal Sheet):**
```
Form {
  Section("Basic Info") {
    TextField("Name", text: $constraint.name)
    Picker("Type", selection: $constraint.type)
    TextField("Priority", value: $constraint.priority)
    Toggle("Enabled", isOn: $constraint.enabled)
  }

  Section("Conditions") {
    ForEach(constraint.conditions) { condition in
      ConditionRow(condition)
      ├─ Picker("Field")
      ├─ Picker("Operator")
      └─ TextField("Value")
    }
    Button("+ Add Condition")
  }

  Section("Action") {
    Picker("Action Type", selection: $actionType)
    if actionType == .block {
      TextField("Reason", text: $blockReason)
    }
    // ... other action-specific fields
  }

  Section {
    Button("Cancel") { dismiss() }
    Button("Save") { saveAndDismiss() }
  }
}
```

**No Simulation Panel** — Deferred to Phase 5.

---

## 1A.6 Exact JSON Schema (MVP)

### File Location

```
~/Library/Application Support/NoesisNoema/policy-constraints.json
```

### Schema Definition

```json
{
  "type": "array",
  "items": {
    "type": "object",
    "required": ["id", "name", "type", "enabled", "priority", "conditions", "action"],
    "properties": {
      "id": {
        "type": "string",
        "format": "uuid"
      },
      "name": {
        "type": "string",
        "minLength": 1
      },
      "type": {
        "type": "string",
        "enum": ["privacy", "cost", "performance", "intent"]
      },
      "enabled": {
        "type": "boolean"
      },
      "priority": {
        "type": "integer",
        "minimum": 1
      },
      "conditions": {
        "type": "array",
        "minItems": 1,
        "items": {
          "type": "object",
          "required": ["field", "operator", "value"],
          "properties": {
            "field": {
              "type": "string",
              "enum": ["content", "token_count", "intent", "privacy_level"]
            },
            "operator": {
              "type": "string",
              "enum": ["contains", "notContains", "equals", "notEquals", "exceeds", "lessThan"]
            },
            "value": {
              "type": "string"
            }
          }
        }
      },
      "action": {
        "type": "object",
        "required": ["type"],
        "properties": {
          "type": {
            "type": "string",
            "enum": ["block", "forceLocal", "forceCloud", "requireConfirmation", "warn"]
          },
          "reason": {
            "type": "string",
            "description": "Required if type == block"
          },
          "prompt": {
            "type": "string",
            "description": "Required if type == requireConfirmation"
          },
          "message": {
            "type": "string",
            "description": "Required if type == warn"
          }
        }
      }
    }
  }
}
```

### Example (Minimal)

```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "name": "Block Sensitive Data",
    "type": "privacy",
    "enabled": true,
    "priority": 1,
    "conditions": [
      {
        "field": "content",
        "operator": "contains",
        "value": "SSN|password"
      }
    ],
    "action": {
      "type": "block",
      "reason": "Contains sensitive data"
    }
  }
]
```

**No additional metadata** (e.g., `createdAt`, `modifiedAt`) in Phase 4.

---

## 1A.7 Explicit Non-Modification Guarantees

### Router is Unchanged

**Statement:**
`Shared/Routing/Router.swift` will **not be modified** in Phase 4.

**Verification:**
- Before: `git diff main -- Shared/Routing/Router.swift` → empty
- After: `git diff main -- Shared/Routing/Router.swift` → empty

**Integration Point:**
The Router receives `PolicyEvaluationResult` from the PolicyEngine, which in turn receives `[PolicyRule]` from `PolicyRulesProvider` (injected into ExecutionCoordinator). The Constraint Editor modifies the JSON file, which is loaded into `PolicyRulesStore` on app startup. No Router code changes required.

---

### PolicyEngine is Unchanged

**Statement:**
`Shared/Policy/PolicyEngine.swift` will **not be modified** in Phase 4.

**Verification:**
- Before: `git diff feature/epic1-policy-engine -- Shared/Policy/PolicyEngine.swift` → empty
- After: `git diff feature/epic1-policy-engine -- Shared/Policy/PolicyEngine.swift` → empty

**Integration Point:**
The PolicyEngine's `evaluate()` function already accepts `rules: [PolicyRule]` as a parameter. The Constraint Editor creates/edits `PolicyRule` instances that are persisted to JSON, then loaded and passed to the PolicyEngine. No PolicyEngine code changes required.

---

### ConstraintEditor Uses Dependency Injection

**Statement:**
The Constraint Editor **does not directly call** the PolicyEngine or Router. It only manipulates the JSON file via `ConstraintStore`.

**Data Flow:**

```
User edits constraint in ConstraintEditorView
  ↓
ConstraintEditorViewModel.saveConstraints()
  ↓
ConstraintStore.save([PolicyRule])
  ↓
Write to policy-constraints.json
  ↓
(On app restart)
  ↓
PolicyRulesStore.init()
  ↓
PolicyRulesStore.loadRules()
  ↓
ConstraintStore.load() -> [PolicyRule]
  ↓
PolicyRulesStore.cachedRules = [...]
  ↓
(During execution)
  ↓
ExecutionCoordinator.execute(...)
  ↓
let rules = policyRulesProvider.getPolicyRules()  ← injected via protocol
  ↓
PolicyEngine.evaluate(question, state, rules)
  ↓
Router.route(question, state, policyResult)
```

**No direct coupling** between ConstraintEditor and PolicyEngine/Router.

**No global mutable state** — `PolicyRulesStore` injected via dependency injection.

---

## 1A.8 MVP Implementation Checklist (Strict)

### Phase 4 Tasks (Non-Negotiable)

- [ ] **Step 1:** Create `EditablePolicyRule` model with converters
- [ ] **Step 2:** Implement `ConstraintStore` (JSON read/write with error handling)
- [ ] **Step 3:** Define `PolicyRulesProvider` protocol and `PolicyRulesStore` implementation
- [ ] **Step 4:** Implement `ConstraintEditorViewModel` (CRUD + validation)
- [ ] **Step 5:** Create `ConstraintEditorView` (simple list)
- [ ] **Step 6:** Create `ConstraintDetailView` (modal edit form)
- [ ] **Step 7:** Integrate: Inject `PolicyRulesStore` into `ExecutionCoordinator`
- [ ] **Step 8:** Write unit tests (model conversion, persistence, validation, error handling)
- [ ] **Step 9:** Write UI tests (CRUD operations)
- [ ] **Step 10:** Document JSON schema and dependency injection pattern

**Estimated Effort:** 12 hours (1.5 days)

**Reduced from original 20 hours** due to:
- No simulation mode (saved 2 hours)
- No master-detail layout (saved 2 hours)
- No template system (saved 2 hours)
- No advanced validation (saved 2 hours)

---

## 1A.9 Acceptance Criteria (MVP)

Phase 4 is **complete** when:

1. ✅ Developer can create a new constraint via UI
2. ✅ Developer can edit an existing constraint
3. ✅ Developer can enable/disable constraints
4. ✅ Developer can delete constraints
5. ✅ Constraints are persisted to `policy-constraints.json`
6. ✅ Constraints are loaded on app startup via `PolicyRulesStore`
7. ✅ Constraints are passed to `PolicyEngine.evaluate()` via dependency injection
8. ✅ Validation prevents saving malformed constraints (name, conditions, action)
9. ✅ Persistence errors handled gracefully (no crashes)
10. ✅ Router is unchanged (verified by `git diff`)
11. ✅ PolicyEngine is unchanged (verified by `git diff`)
12. ✅ No global mutable state (verified by code review)
13. ✅ Unit tests pass (model conversion, persistence, validation, error handling)
14. ✅ UI tests pass (CRUD operations)

**Not Required for Phase 4:**
- ❌ Simulation mode
- ❌ Master-detail layout
- ❌ Priority conflict detection
- ❌ Execution history integration
- ❌ Template library
- ❌ Advanced operators (OR logic, regex)

---

## 1A.10 Summary: What Changed from Original Design

### Original Design (Sections 1-9)

- Master-detail layout
- Simulation mode with determinism verification
- Template library
- Advanced validation (priority conflicts, dependency checking)
- Execution history integration
- Real-time constraint reload
- Import/export functionality

**Estimated Effort:** 20 hours (2.5 days)

### MVP Design (This Section)

- Simple list with modal edit sheet
- No simulation mode (deferred to Phase 5)
- No template library (deferred to Phase 5)
- Basic validation only (name, conditions, action)
- No execution history integration (deferred to Phase 5)
- Manual reload only
- No import/export (deferred to Phase 6)

**Estimated Effort:** 12 hours (1.5 days)

**Reduction:** 40% less scope, 40% less time

### Why This Matters

The MVP design:
1. **Validates core architecture** (EditablePolicyRule ↔ PolicyRule conversion)
2. **Proves integration works** (ConstraintStore → AppSettings → PolicyEngine)
3. **Demonstrates UI feasibility** (SwiftUI CRUD operations)
4. **Maintains determinism guarantees** (PolicyEngine unchanged)
5. **Enables incremental refinement** (Phase 5 adds simulation, Phase 6 adds templates)

**Phase 4 is a foundation, not a complete product.** It proves the concept and enables future enhancement without rework.

---

# SECTION 2 — Architecture

## 2.1 Component Overview

The Constraint Editor is composed of four layers:

### Layer 1: View Layer (SwiftUI)

**Components:**
- `ConstraintEditorView` — Main view containing list + editor + simulation
- `ConstraintListView` — Displays all constraints with enable/disable toggles
- `ConstraintDetailView` — Form for editing a single constraint
- `SimulationView` — Input test data and display results

**Responsibility:**
- Render UI elements
- Capture user input
- Display validation errors
- Delegate business logic to ViewModel

---

### Layer 2: ViewModel Layer

**Components:**
- `ConstraintEditorViewModel` — Manages constraint list and editor state
- `SimulationViewModel` — Manages simulation mode state and execution

**Responsibility:**
- Load constraints from storage
- Save constraints to storage
- Validate constraint structure
- Convert between `EditablePolicyRule` and `PolicyRule`
- Execute `PolicyEngine.evaluate()` for simulation
- Provide observable state for SwiftUI views

---

### Layer 3: Domain Model Layer

**Components:**
- `EditablePolicyRule` — UI-facing model with mutable fields
- `PolicyRule` — Immutable domain model (already exists in `Shared/Policy/PolicyRule.swift`)
- `ConstraintValidationError` — Validation error types

**Responsibility:**
- Define data structures for UI editing
- Map between UI model and domain model
- Enforce validation rules

---

### Layer 4: Persistence Layer

**Components:**
- `ConstraintStore` — Reads/writes constraints to JSON file
- `ConstraintJSONCodec` — Encodes/decodes `[PolicyRule]` to/from JSON

**Responsibility:**
- Persist constraints to Application Support directory
- Load constraints on app startup
- Handle file I/O errors gracefully

---

## 2.2 Component Diagram

```
┌───────────────────────────────────────────────────────────────────┐
│                       View Layer (SwiftUI)                         │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐ │
│  │ ConstraintEditor │  │ ConstraintDetail │  │ SimulationView   │ │
│  │ View             │  │ View             │  │                  │ │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘ │
└───────────┼────────────────────┼────────────────────┼─────────────┘
            │                    │                    │
            └────────────────────┼────────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │   ViewModel Layer       │
                    │  ┌────────────────────┐ │
                    │  │ ConstraintEditor   │ │
                    │  │ ViewModel          │ │
                    │  └─────────┬──────────┘ │
                    │  ┌─────────▼──────────┐ │
                    │  │ Simulation         │ │
                    │  │ ViewModel          │ │
                    │  └─────────┬──────────┘ │
                    └────────────┼────────────┘
                                 │
            ┌────────────────────┼────────────────────┐
            │                    │                    │
┌───────────▼───────┐  ┌─────────▼────────┐  ┌───────▼──────────┐
│  Domain Model      │  │ PolicyEngine     │  │ Persistence      │
│  ┌───────────────┐ │  │ (pure function)  │  │  ┌─────────────┐ │
│  │ Editable      │ │  │                  │  │  │ Constraint  │ │
│  │ PolicyRule    │ │  │ evaluate()       │  │  │ Store       │ │
│  └───────────────┘ │  │                  │  │  └─────────────┘ │
│  ┌───────────────┐ │  └──────────────────┘  │  ┌─────────────┐ │
│  │ PolicyRule    │ │                         │  │ JSON Codec  │ │
│  │ (immutable)   │ │                         │  └─────────────┘ │
│  └───────────────┘ │                         └──────────────────┘
└───────────────────┘
```

---

## 2.3 EditablePolicyRule Model (UI-Facing)

The `EditablePolicyRule` is a **mutable** version of `PolicyRule` designed for UI editing.

### Why a Separate Model?

**Problem:**
`PolicyRule` (in `Shared/Policy/PolicyRule.swift`) is **immutable** (`let` properties), which makes it unsuitable for SwiftUI forms that require `@Binding` to mutable properties.

**Solution:**
Create a parallel `EditablePolicyRule` struct with `var` properties that can be edited via SwiftUI bindings, then convert to `PolicyRule` when saving.

### EditablePolicyRule Definition

```swift
/// Mutable version of PolicyRule for UI editing
struct EditablePolicyRule: Identifiable {
    var id: UUID
    var name: String
    var type: ConstraintType
    var enabled: Bool
    var priority: Int
    var conditions: [EditableConditionRule]
    var action: EditableConstraintAction

    init(
        id: UUID = UUID(),
        name: String = "",
        type: ConstraintType = .privacy,
        enabled: Bool = true,
        priority: Int = 1,
        conditions: [EditableConditionRule] = [],
        action: EditableConstraintAction = .allow
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.enabled = enabled
        self.priority = priority
        self.conditions = conditions
        self.action = action
    }
}

/// Mutable version of ConditionRule
struct EditableConditionRule: Identifiable {
    var id: UUID = UUID()
    var field: String
    var `operator`: Operator
    var value: String

    init(field: String = "content", operator: Operator = .contains, value: String = "") {
        self.field = field
        self.operator = `operator`
        self.value = value
    }
}

/// Mutable version of ConstraintAction
enum EditableConstraintAction {
    case allow
    case block(reason: String)
    case forceLocal
    case forceCloud
    case requireConfirmation(prompt: String)
    case warn(message: String)
}
```

---

### Mapping Between EditablePolicyRule and PolicyRule

```swift
extension EditablePolicyRule {
    /// Convert to immutable PolicyRule for storage and evaluation
    func toPolicyRule() -> PolicyRule {
        let immutableConditions = conditions.map { editableCondition in
            ConditionRule(
                field: editableCondition.field,
                operator: editableCondition.operator,
                value: editableCondition.value
            )
        }

        let immutableAction: ConstraintAction
        switch action {
        case .allow:
            // Note: PolicyRule doesn't have an .allow action
            // This is a temporary state in the editor
            // When saving, we skip rules with .allow action
            fatalError("Cannot save constraint with .allow action - this is invalid")
        case .block(let reason):
            immutableAction = .block(reason: reason)
        case .forceLocal:
            immutableAction = .forceLocal
        case .forceCloud:
            immutableAction = .forceCloud
        case .requireConfirmation(let prompt):
            immutableAction = .requireConfirmation(prompt: prompt)
        case .warn(let message):
            immutableAction = .warn(message: message)
        }

        return PolicyRule(
            id: id,
            name: name,
            type: type,
            enabled: enabled,
            priority: priority,
            conditions: immutableConditions,
            action: immutableAction
        )
    }

    /// Create from immutable PolicyRule
    init(from policyRule: PolicyRule) {
        self.id = policyRule.id
        self.name = policyRule.name
        self.type = policyRule.type
        self.enabled = policyRule.enabled
        self.priority = policyRule.priority

        self.conditions = policyRule.conditions.map { condition in
            EditableConditionRule(
                field: condition.field,
                operator: condition.operator,
                value: condition.value
            )
        }

        switch policyRule.action {
        case .block(let reason):
            self.action = .block(reason: reason)
        case .forceLocal:
            self.action = .forceLocal
        case .forceCloud:
            self.action = .forceCloud
        case .requireConfirmation(let prompt):
            self.action = .requireConfirmation(prompt: prompt)
        case .warn(let message):
            self.action = .warn(message: message)
        }
    }
}
```

---

## 2.4 ConstraintEditorViewModel

The ViewModel manages constraint state and coordinates between UI and domain models.

### Responsibilities

1. **Load Constraints**
   - Load `[PolicyRule]` from `ConstraintStore` on init
   - Convert to `[EditablePolicyRule]` for UI editing

2. **Save Constraints**
   - Convert `[EditablePolicyRule]` to `[PolicyRule]`
   - Validate before saving
   - Persist to `ConstraintStore`

3. **CRUD Operations**
   - Add new constraint
   - Update existing constraint
   - Delete constraint
   - Enable/disable constraint

4. **Validation**
   - Ensure name is not empty
   - Ensure at least one condition exists
   - Ensure action is configured correctly (e.g., block has reason)
   - Warn if priority conflicts exist

5. **Observable State**
   - `@Published` properties for SwiftUI reactive updates

### Implementation Skeleton

```swift
@MainActor
class ConstraintEditorViewModel: ObservableObject {
    // MARK: - Published State

    @Published var constraints: [EditablePolicyRule] = []
    @Published var selectedConstraintId: UUID? = nil
    @Published var validationErrors: [ConstraintValidationError] = []
    @Published var isSaving: Bool = false
    @Published var saveError: Error? = nil

    // MARK: - Dependencies

    private let constraintStore: ConstraintStore

    init(constraintStore: ConstraintStore = ConstraintStore.shared) {
        self.constraintStore = constraintStore
        loadConstraints()
    }

    // MARK: - Load/Save

    func loadConstraints() {
        do {
            let policyRules = try constraintStore.load()
            self.constraints = policyRules.map { EditablePolicyRule(from: $0) }
        } catch {
            print("Failed to load constraints: \(error)")
            self.constraints = []
        }
    }

    func saveConstraints() {
        isSaving = true
        saveError = nil

        // Validate all constraints
        validationErrors = validateAll()
        guard validationErrors.isEmpty else {
            isSaving = false
            return
        }

        // Convert to PolicyRule
        let policyRules = constraints.compactMap { editable -> PolicyRule? in
            do {
                return try editable.toPolicyRule()
            } catch {
                return nil
            }
        }

        // Persist
        do {
            try constraintStore.save(policyRules)
            isSaving = false
        } catch {
            saveError = error
            isSaving = false
        }
    }

    // MARK: - CRUD Operations

    func addConstraint() {
        let newConstraint = EditablePolicyRule(
            name: "New Constraint",
            priority: (constraints.map { $0.priority }.max() ?? 0) + 1
        )
        constraints.append(newConstraint)
        selectedConstraintId = newConstraint.id
    }

    func deleteConstraint(id: UUID) {
        constraints.removeAll { $0.id == id }
        if selectedConstraintId == id {
            selectedConstraintId = nil
        }
    }

    func toggleConstraint(id: UUID) {
        if let index = constraints.firstIndex(where: { $0.id == id }) {
            constraints[index].enabled.toggle()
        }
    }

    // MARK: - Validation

    func validateAll() -> [ConstraintValidationError] {
        var errors: [ConstraintValidationError] = []

        for constraint in constraints {
            // Name cannot be empty
            if constraint.name.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append(.emptyName(constraintId: constraint.id))
            }

            // Must have at least one condition
            if constraint.conditions.isEmpty {
                errors.append(.noConditions(constraintId: constraint.id))
            }

            // Action must be valid
            switch constraint.action {
            case .block(let reason):
                if reason.trimmingCharacters(in: .whitespaces).isEmpty {
                    errors.append(.blockWithoutReason(constraintId: constraint.id))
                }
            case .requireConfirmation(let prompt):
                if prompt.trimmingCharacters(in: .whitespaces).isEmpty {
                    errors.append(.confirmationWithoutPrompt(constraintId: constraint.id))
                }
            case .warn(let message):
                if message.trimmingCharacters(in: .whitespaces).isEmpty {
                    errors.append(.warnWithoutMessage(constraintId: constraint.id))
                }
            default:
                break
            }
        }

        return errors
    }
}

enum ConstraintValidationError: Error, Identifiable {
    case emptyName(constraintId: UUID)
    case noConditions(constraintId: UUID)
    case blockWithoutReason(constraintId: UUID)
    case confirmationWithoutPrompt(constraintId: UUID)
    case warnWithoutMessage(constraintId: UUID)

    var id: String {
        switch self {
        case .emptyName(let id): return "emptyName-\(id)"
        case .noConditions(let id): return "noConditions-\(id)"
        case .blockWithoutReason(let id): return "blockWithoutReason-\(id)"
        case .confirmationWithoutPrompt(let id): return "confirmationWithoutPrompt-\(id)"
        case .warnWithoutMessage(let id): return "warnWithoutMessage-\(id)"
        }
    }

    var message: String {
        switch self {
        case .emptyName: return "Constraint name cannot be empty"
        case .noConditions: return "At least one condition is required"
        case .blockWithoutReason: return "Block action requires a reason"
        case .confirmationWithoutPrompt: return "Confirmation action requires a prompt"
        case .warnWithoutMessage: return "Warning action requires a message"
        }
    }
}
```

---

## 2.5 Persistence Strategy

### JSON Storage Location

Constraints are stored in the **Application Support** directory:

```
~/Library/Application Support/NoesisNoema/policy-constraints.json
```

**Rationale:**
- Application Support is the standard macOS location for app-generated data
- Survives app updates
- Excluded from iCloud backup by default (can be changed later)
- Easy to inspect and edit manually for debugging

---

### JSON Schema

```json
[
  {
    "id": "123e4567-e89b-12d3-a456-426614174000",
    "name": "Block Sensitive Data",
    "type": "privacy",
    "enabled": true,
    "priority": 1,
    "conditions": [
      {
        "field": "content",
        "operator": "contains",
        "value": "SSN|credit card|password"
      }
    ],
    "action": {
      "type": "block",
      "reason": "Prompt contains sensitive data patterns"
    }
  },
  {
    "id": "223e4567-e89b-12d3-a456-426614174001",
    "name": "Force Local for Personal Queries",
    "type": "privacy",
    "enabled": true,
    "priority": 2,
    "conditions": [
      {
        "field": "content",
        "operator": "contains",
        "value": "my|I am|personal"
      }
    ],
    "action": {
      "type": "forceLocal"
    }
  }
]
```

---

### ConstraintStore Implementation

```swift
class ConstraintStore {
    static let shared = ConstraintStore()

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL = fileURL {
            self.fileURL = fileURL
        } else {
            // Default: Application Support directory
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!

            let noesisDir = appSupport.appendingPathComponent("NoesisNoema", isDirectory: true)
            try? FileManager.default.createDirectory(at: noesisDir, withIntermediateDirectories: true)

            self.fileURL = noesisDir.appendingPathComponent("policy-constraints.json")
        }
    }

    func load() throws -> [PolicyRule] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // Return empty array if file doesn't exist yet
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        return try decoder.decode([PolicyRule].self, from: data)
    }

    func save(_ rules: [PolicyRule]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(rules)
        try data.write(to: fileURL, options: .atomic)
    }
}
```

---

### Initial Default Constraints

On first launch, if `policy-constraints.json` does not exist, the app should create it with **example constraints**:

```swift
func loadDefaultConstraints() -> [PolicyRule] {
    [
        PolicyRule(
            name: "Example: Block Sensitive Keywords",
            type: .privacy,
            enabled: false,  // Disabled by default
            priority: 1,
            conditions: [
                ConditionRule(field: "content", operator: .contains, value: "SSN|password|credit card")
            ],
            action: .block(reason: "Contains sensitive data")
        ),
        PolicyRule(
            name: "Example: Warn on Large Queries",
            type: .cost,
            enabled: false,
            priority: 2,
            conditions: [
                ConditionRule(field: "token_count", operator: .exceeds, value: "5000")
            ],
            action: .warn(message: "Large query may incur cloud costs")
        )
    ]
}
```

---

## 2.6 Simulation Mode Architecture

Simulation Mode allows developers to **test policy evaluation** without triggering actual execution.

### Components

1. **SimulationViewModel**
   - Manages test input state (question, runtime state)
   - Invokes `PolicyEngine.evaluate()`
   - Stores and displays results

2. **SimulationView**
   - Input fields for test question content, privacy level, intent
   - Input fields for runtime state (network state, token threshold)
   - Button to run simulation
   - Display area for results

---

### SimulationViewModel Implementation

```swift
@MainActor
class SimulationViewModel: ObservableObject {
    // MARK: - Test Inputs

    @Published var testQuestionContent: String = ""
    @Published var testPrivacyLevel: PrivacyLevel = .auto
    @Published var testIntent: Intent? = nil

    @Published var testNetworkState: NetworkState = .online
    @Published var testTokenThreshold: Int = 4096
    @Published var testLocalModelAvailable: Bool = true

    // MARK: - Results

    @Published var simulationResult: PolicyEvaluationResult? = nil
    @Published var triggeredRuleIds: [UUID] = []
    @Published var effectiveActionDescription: String = ""
    @Published var warningsDescription: String = ""
    @Published var requiresConfirmation: Bool = false

    // MARK: - Dependencies

    private let rules: [PolicyRule]

    init(rules: [PolicyRule]) {
        self.rules = rules
    }

    // MARK: - Simulation Execution

    func runSimulation() {
        // Construct test question
        let question = NoemaQuestion(
            content: testQuestionContent,
            privacyLevel: testPrivacyLevel,
            intent: testIntent,
            sessionId: UUID() // Dummy session ID for simulation
        )

        // Construct test runtime state
        let localCapability = LocalModelCapability(
            modelName: "llama-3.2-8b",
            maxTokens: 4096,
            supportedIntents: [.informational, .retrieval],
            available: testLocalModelAvailable
        )

        let runtimeState = RuntimeState(
            localModelCapability: localCapability,
            networkState: testNetworkState,
            tokenThreshold: testTokenThreshold,
            cloudModelName: "gpt-4"
        )

        // Run PolicyEngine.evaluate()
        do {
            let result = try PolicyEngine.evaluate(
                question: question,
                runtimeState: runtimeState,
                rules: rules
            )

            // Store results
            self.simulationResult = result
            self.triggeredRuleIds = result.appliedConstraints
            self.requiresConfirmation = result.requiresConfirmation

            // Format effective action description
            self.effectiveActionDescription = describeAction(result.effectiveAction)

            // Format warnings
            if result.warnings.isEmpty {
                self.warningsDescription = "None"
            } else {
                self.warningsDescription = result.warnings.joined(separator: "\n")
            }

        } catch {
            // Handle policy violation error
            if let routingError = error as? RoutingError,
               case .policyViolation(let reason) = routingError {
                self.effectiveActionDescription = "BLOCKED: \(reason)"
            } else {
                self.effectiveActionDescription = "ERROR: \(error.localizedDescription)"
            }
        }
    }

    private func describeAction(_ action: PolicyAction) -> String {
        switch action {
        case .allow:
            return "ALLOW (routing proceeds normally)"
        case .block(let reason):
            return "BLOCK: \(reason)"
        case .forceLocal:
            return "FORCE LOCAL (route to local model)"
        case .forceCloud:
            return "FORCE CLOUD (route to cloud model)"
        }
    }
}
```

---

### SimulationView Layout

```
┌─────────────────────────────────────────────────────────┐
│ Simulation Mode                                          │
├─────────────────────────────────────────────────────────┤
│                                                          │
│ Test Question:                                           │
│ ┌────────────────────────────────────────────────────┐  │
│ │ What is the capital of France?                     │  │
│ └────────────────────────────────────────────────────┘  │
│                                                          │
│ Privacy Level: [Auto ▼]                                 │
│ Intent: [Informational ▼]                               │
│                                                          │
│ Runtime State:                                           │
│ Network: [Online ▼]                                     │
│ Token Threshold: [4096      ]                           │
│ Local Model Available: [✓]                              │
│                                                          │
│                     [Run Simulation]                     │
│                                                          │
├─────────────────────────────────────────────────────────┤
│ Results:                                                 │
├─────────────────────────────────────────────────────────┤
│                                                          │
│ Effective Action: ALLOW (routing proceeds normally)     │
│                                                          │
│ Triggered Rules: None                                   │
│                                                          │
│ Warnings: None                                          │
│                                                          │
│ Requires Confirmation: No                               │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

### Determinism Verification

To verify determinism, SimulationView should include a **"Run 10x"** button that:
1. Runs `PolicyEngine.evaluate()` 10 times with the same inputs
2. Verifies that all 10 results are identical
3. Displays "✅ DETERMINISTIC" or "❌ NON-DETERMINISTIC" badge

```swift
func verifyDeterminism() {
    var results: [PolicyEvaluationResult] = []

    for _ in 0..<10 {
        // Run simulation (reuse existing logic)
        runSimulation()
        if let result = simulationResult {
            results.append(result)
        }
    }

    // Check if all results are identical
    guard !results.isEmpty else { return }

    let firstResult = results[0]
    let allIdentical = results.allSatisfy { result in
        result.effectiveAction == firstResult.effectiveAction &&
        result.appliedConstraints == firstResult.appliedConstraints &&
        result.warnings == firstResult.warnings &&
        result.requiresConfirmation == firstResult.requiresConfirmation
    }

    if allIdentical {
        print("✅ Policy evaluation is DETERMINISTIC")
    } else {
        print("❌ Policy evaluation is NON-DETERMINISTIC (bug!)")
    }
}
```

---

# SECTION 3 — UI Design Specification

## 3.1 ConstraintEditorView (Main View)

### Layout

```
┌──────────────────────────────────────────────────────────────────────┐
│ Constraint Editor                                         [+ New]     │
├───────────────────────┬──────────────────────────────────────────────┤
│                       │                                              │
│ Constraint List       │ Constraint Detail Editor                     │
│ (Master)              │ (Detail)                                     │
│                       │                                              │
│ [✓] Block Sensitive   │ Name: [Block Sensitive Data              ]  │
│     Data              │                                              │
│     Priority: 1       │ Type: [Privacy ▼]                           │
│     Privacy           │ Priority: [1  ]                              │
│                       │ Enabled: [✓]                                 │
│ [✓] Warn on Large     │                                              │
│     Queries           │ Conditions (All must match):                 │
│     Priority: 2       │ ┌──────────────────────────────────────────┐ │
│     Cost              │ │ Field: [content ▼]                       │ │
│                       │ │ Operator: [contains ▼]                   │ │
│ [ ] Force Local       │ │ Value: [SSN|password|credit card      ]  │ │
│     (Disabled)        │ │                               [Remove]   │ │
│     Priority: 3       │ └──────────────────────────────────────────┘ │
│     Privacy           │                                  [+ Add Condition] │
│                       │                                              │
│                       │ Action:                                      │
│                       │ [Block Execution ▼]                         │
│                       │ Reason: [Contains sensitive data         ]  │
│                       │                                              │
│                       │                     [Cancel]  [Save]         │
│                       │                                              │
├───────────────────────┴──────────────────────────────────────────────┤
│ Simulation Mode                                                      │
│ (Collapsible Section)                                   [Expand ▼]   │
└──────────────────────────────────────────────────────────────────────┘
```

---

### Master-Detail Pattern

- **Master (Left):** List of all constraints with quick enable/disable toggle
- **Detail (Right):** Edit form for selected constraint
- **Bottom:** Collapsible simulation mode panel

---

### Constraint List Item

Each item in the list displays:
- **Checkbox:** Enable/disable toggle
- **Name:** Constraint name
- **Priority:** Priority number (for sorting)
- **Type:** Badge indicating type (Privacy, Cost, Performance, Intent)
- **Action:** Icon indicating action type (🚫 Block, ⬅️ Force Local, ☁️ Force Cloud, ⚠️ Warn, ❓ Confirm)

---

## 3.2 ConstraintDetailView (Editor Form)

### Fields

1. **Name** (TextField)
   - Required
   - Validation: Cannot be empty

2. **Type** (Picker)
   - Options: Privacy, Cost, Performance, Intent

3. **Priority** (TextField with number formatter)
   - Required
   - Validation: Must be positive integer
   - Warning if duplicate priority exists

4. **Enabled** (Toggle)
   - Default: On

5. **Conditions** (List of condition rows)
   - Each condition row has:
     - **Field** (Picker): content, token_count, intent, privacy_level
     - **Operator** (Picker): contains, notContains, exceeds, lessThan, equals, notEquals
     - **Value** (TextField): String value
     - **Remove button**
   - **Add Condition button** at bottom

6. **Action** (Picker with conditional fields)
   - Options: Block, Force Local, Force Cloud, Require Confirmation, Warn
   - **If Block:** Show "Reason" text field (required)
   - **If Require Confirmation:** Show "Prompt" text field (required)
   - **If Warn:** Show "Message" text field (required)

---

### Validation Feedback

Validation errors are displayed as inline red text below the invalid field:
- "Name cannot be empty"
- "At least one condition is required"
- "Block action requires a reason"

---

## 3.3 SimulationView (Test Panel)

### Layout

```
┌──────────────────────────────────────────────────────────────────────┐
│ Simulation Mode                                          [Collapse ▲]│
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│ Test Input:                                                           │
│ ┌─────────────────────────────────────────────────────────────────┐  │
│ │ Question: [What is the capital of France?                    ]  │  │
│ │ Privacy Level: [Auto ▼]  Intent: [Informational ▼]            │  │
│ │ Network: [Online ▼]  Token Threshold: [4096  ]                 │  │
│ │ Local Model Available: [✓]                                     │  │
│ └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│          [Run Once]    [Run 10x (Verify Determinism)]                │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│ Results:                                                              │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│ Effective Action: ALLOW (routing proceeds normally)                  │
│                                                                       │
│ Triggered Rules: None                                                │
│                                                                       │
│ Warnings: None                                                       │
│                                                                       │
│ Requires Confirmation: No                                            │
│                                                                       │
│ Determinism: ✅ VERIFIED (10 identical results)                      │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

---

### Triggered Rules Display

When rules are triggered, show:
- Rule name
- Rule priority
- Matched conditions

Example:
```
Triggered Rules:
1. Block Sensitive Data (Priority 1)
   - Matched: content contains "password"
```

---

# SECTION 4 — Integration Strategy

## 4.1 How Edited Rules Are Injected Into Router

### Current Production Flow (Without Constraint Editor)

```
User Input
  ↓
NoemaQuestion created
  ↓
PolicyEngine.evaluate(question, state, rules: [])  // Empty rules
  ↓
Router.route(question, state, policyResult)
  ↓
Execution
```

**Problem:** Rules are hardcoded or empty.

---

### New Flow (With Constraint Editor)

```
App Startup
  ↓
ConstraintStore.load()  // Load rules from JSON
  ↓
Store rules in AppSettings (shared state)
  ↓
    ┌─────────────────────────────────────────┐
    │ User Input                              │
    ↓                                         │
NoemaQuestion created                         │
    ↓                                         │
PolicyEngine.evaluate(                        │
    question,                                 │
    state,                                    │
    rules: AppSettings.shared.policyRules  ← ─┘
)
    ↓
Router.route(question, state, policyResult)
    ↓
Execution
```

---

### AppSettings Integration

```swift
@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var policyRules: [PolicyRule] = []

    private let constraintStore = ConstraintStore.shared

    init() {
        loadPolicyRules()
    }

    func loadPolicyRules() {
        do {
            self.policyRules = try constraintStore.load()
        } catch {
            print("Failed to load policy rules: \(error)")
            self.policyRules = []
        }
    }

    func reloadPolicyRules() {
        loadPolicyRules()
    }
}
```

---

### ConstraintEditor Save Flow

When the user saves constraints in the editor:

1. ConstraintEditorViewModel validates constraints
2. ConstraintEditorViewModel writes to ConstraintStore
3. ConstraintEditorViewModel notifies AppSettings to reload
4. AppSettings updates `policyRules` (triggers @Published update)
5. All subsequent executions use the new rules

---

### Code Integration Point

In the execution coordinator (or wherever PolicyEngine is invoked):

```swift
// OLD (hardcoded rules):
let policyResult = try PolicyEngine.evaluate(
    question: question,
    runtimeState: runtimeState,
    rules: []  // ❌ No rules
)

// NEW (rules from editor):
let policyResult = try PolicyEngine.evaluate(
    question: question,
    runtimeState: runtimeState,
    rules: AppSettings.shared.policyRules  // ✅ Rules from JSON
)
```

---

## 4.2 Default Rules on Startup

On first app launch (when `policy-constraints.json` doesn't exist):

1. Create default constraints (see Section 2.5)
2. Save to `ConstraintStore`
3. Load into `AppSettings.shared.policyRules`

**Rationale:**
- Provides example constraints for developers to learn from
- All default constraints are **disabled** by default (won't affect production)
- User can enable/edit as needed

---

# SECTION 5 — Determinism Guarantees

## 5.1 Editor Must Not Modify PolicyEngine Purity

**Critical Invariant:**
The PolicyEngine **must remain pure** regardless of whether constraints are created via code or via the Constraint Editor.

### How This Is Enforced

1. **PolicyEngine is a pure static function**
   - No dependencies on UI state
   - No dependencies on AppSettings
   - Only accepts `rules: [PolicyRule]` as parameter

2. **Constraint Editor operates on the same data structures**
   - `EditablePolicyRule` converts to `PolicyRule`
   - No editor-specific metadata is injected into `PolicyRule`
   - `PolicyRule` remains immutable and Codable

3. **Simulation Mode calls PolicyEngine directly**
   - No wrapper or proxy
   - Same function signature as production
   - Same determinism guarantees

---

### Test to Verify Purity

```swift
func testConstraintEditorDoesNotAffectDeterminism() {
    // Create a constraint via editor
    let editable = EditablePolicyRule(
        name: "Test",
        type: .privacy,
        enabled: true,
        priority: 1,
        conditions: [
            EditableConditionRule(field: "content", operator: .contains, value: "test")
        ],
        action: .warn(message: "Test warning")
    )

    // Convert to PolicyRule
    let policyRule = editable.toPolicyRule()

    // Create test question
    let question = NoemaQuestion(
        content: "This is a test",
        privacyLevel: .auto,
        sessionId: UUID()
    )

    let state = makeRuntimeState()

    // Run PolicyEngine 10 times
    var results: [PolicyEvaluationResult] = []
    for _ in 0..<10 {
        let result = try! PolicyEngine.evaluate(
            question: question,
            runtimeState: state,
            rules: [policyRule]
        )
        results.append(result)
    }

    // Verify all results are identical
    let firstResult = results[0]
    for result in results.dropFirst() {
        XCTAssertEqual(result.effectiveAction, firstResult.effectiveAction)
        XCTAssertEqual(result.appliedConstraints, firstResult.appliedConstraints)
    }
}
```

---

## 5.2 UI Layer Is Stateful, Engine Is Not

### Clear Separation of Concerns

| Layer           | Statefulness | Mutability | Determinism |
|----------------|--------------|------------|-------------|
| **PolicyEngine** | Stateless    | Immutable  | Deterministic |
| **Router**       | Stateless    | Immutable  | Deterministic |
| **ConstraintEditorViewModel** | Stateful | Mutable | Non-deterministic |
| **SimulationViewModel** | Stateful | Mutable | Non-deterministic |

---

### Enforcement Mechanisms

1. **PolicyEngine is a `struct` with `static func`**
   - Cannot instantiate
   - No instance state
   - No mutation

2. **PolicyRule is a `struct` with `let` properties**
   - Immutable after creation
   - Cannot be modified after passing to PolicyEngine

3. **EditablePolicyRule is separate from PolicyRule**
   - Mutation happens in UI layer only
   - Conversion to PolicyRule creates a new immutable copy

---

# SECTION 6 — Future Extensions (Phase 5+)

## 6.1 Execution History Integration

**Goal:** Show which constraints triggered in past executions.

**Requirements (Future Phase):**
- Execution logs include `appliedConstraints: [UUID]`
- Constraint Editor displays "Last Triggered" timestamp
- Clicking a constraint shows execution history entries where it triggered

**Not Included in Phase 4:**
- Phase 4 focuses on **constraint creation and testing**
- Execution history integration requires ExecutionCoordinator changes (Phase 5)

---

## 6.2 Trace ID Surfacing

**Goal:** Link constraints to specific execution attempts via `trace_id`.

**Requirements (Future Phase):**
- Execution logs include `trace_id`
- Simulation Mode displays `trace_id` for reproducibility
- Constraint Editor can search for constraints by `trace_id`

**Not Included in Phase 4:**
- Phase 4 simulation mode does not generate real `trace_id` (uses dummy UUID)

---

## 6.3 Rule Provenance

**Goal:** Track who created/modified each constraint and when.

**Requirements (Future Phase):**
- Add `createdAt`, `modifiedAt`, `createdBy` fields to PolicyRule
- Display in Constraint Editor as read-only metadata
- Enable audit trail for compliance

**Not Included in Phase 4:**
- Phase 4 focuses on functional implementation
- Provenance metadata deferred to Phase 6+

---

## 6.4 Constraint Templates Library

**Goal:** Pre-defined constraint templates for common use cases.

**Requirements (Future Phase):**
- "Block Sensitive Data" template
- "Limit Cloud Costs" template
- "Force Local for Personal Queries" template
- User can select template and customize

**Not Included in Phase 4:**
- Phase 4 includes example constraints in JSON
- Templates UI deferred to Phase 5

---

## 6.5 Advanced Condition Operators

**Goal:** Support regex patterns and OR logic.

**Requirements (Future Phase):**
- Regex operator for complex pattern matching
- OR logic between conditions (current: only AND)
- Nested condition groups

**Not Included in Phase 4:**
- Phase 4 uses existing operators: contains, exceeds, equals, etc.
- Advanced operators require PolicyEngine changes (Phase 6+)

---

## 6.6 Constraint Import/Export

**Goal:** Share constraints between devices or users.

**Requirements (Future Phase):**
- Export constraints as JSON file
- Import constraints from JSON file
- Cloud sync (iCloud or custom backend)

**Not Included in Phase 4:**
- Phase 4 stores constraints locally only
- Import/export deferred to Phase 6+

---

# SECTION 7 — Implementation Checklist

## 7.1 Phase 4 Tasks (In Order)

### Step 1: Domain Models
- [ ] Create `EditablePolicyRule` struct
- [ ] Create `EditableConditionRule` struct
- [ ] Create `EditableConstraintAction` enum
- [ ] Implement `toPolicyRule()` and `init(from:)` converters
- [ ] Write unit tests for model conversion

### Step 2: Persistence Layer
- [ ] Implement `ConstraintStore` with JSON read/write
- [ ] Write unit tests for ConstraintStore
- [ ] Create default constraints JSON
- [ ] Verify JSON schema matches PolicyRule Codable

### Step 3: ViewModel Layer
- [ ] Implement `ConstraintEditorViewModel`
- [ ] Implement CRUD operations (add, edit, delete, toggle)
- [ ] Implement validation logic
- [ ] Implement save/load from ConstraintStore
- [ ] Write unit tests for ViewModel

### Step 4: Simulation ViewModel
- [ ] Implement `SimulationViewModel`
- [ ] Implement `runSimulation()` method
- [ ] Implement `verifyDeterminism()` method
- [ ] Write unit tests for SimulationViewModel

### Step 5: View Layer (macOS)
- [ ] Create `ConstraintEditorView` (master-detail layout)
- [ ] Create `ConstraintListView` (master)
- [ ] Create `ConstraintDetailView` (detail editor)
- [ ] Create `SimulationView` (test panel)
- [ ] Implement validation error display
- [ ] Write UI tests for CRUD operations

### Step 6: Integration
- [ ] Add `policyRules` to `AppSettings`
- [ ] Modify execution coordinator to use `AppSettings.shared.policyRules`
- [ ] Test end-to-end: edit constraint → save → execute question → verify rule applied
- [ ] Write integration tests

### Step 7: Documentation
- [ ] Document constraint JSON schema
- [ ] Document EditablePolicyRule API
- [ ] Add inline code comments
- [ ] Create README for constraint editor
- [ ] Update EPIC1 design doc with Phase 4 completion status

---

## 7.2 Acceptance Criteria (Definition of Done)

Phase 4 is **complete** when:

1. ✅ Developer can create, edit, delete, and toggle constraints via UI
2. ✅ Constraints are persisted to JSON and loaded on startup
3. ✅ Simulation Mode correctly invokes PolicyEngine.evaluate()
4. ✅ Simulation Mode verifies determinism (10x test)
5. ✅ Validation prevents saving malformed constraints
6. ✅ Integration test confirms constraints apply in production execution
7. ✅ PolicyEngine remains pure (no UI dependencies)
8. ✅ Router is not modified
9. ✅ Unit tests pass (100% coverage for ViewModels)
10. ✅ UI tests pass (CRUD operations and simulation)
11. ✅ Documentation is complete

---

## 7.3 Estimated Effort

| Task | Estimated Time |
|------|----------------|
| Domain Models + Tests | 2 hours |
| Persistence Layer + Tests | 2 hours |
| ViewModel Layer + Tests | 4 hours |
| Simulation ViewModel + Tests | 2 hours |
| View Layer (macOS) | 6 hours |
| Integration + Tests | 3 hours |
| Documentation | 1 hour |
| **Total** | **20 hours (2.5 days)** |

---

# SECTION 8 — Open Design Questions

## 8.1 Priority Conflict Handling

**Question:** What should happen if two constraints have the same priority?

**Current Behavior (Section 3.7 of EPIC1 design):**
- Constraints with same priority are sorted by UUID (lexicographical)
- This ensures determinism but is not user-friendly

**Options:**
1. **Warn but allow** (Recommended for Phase 4)
   - Display warning in UI: "Constraint 'X' and 'Y' have the same priority"
   - User can choose to change priorities or accept UUID ordering
2. **Enforce uniqueness**
   - Prevent saving if duplicate priorities exist
   - Auto-increment priority when adding new constraint
3. **Display order explicitly**
   - Show evaluation order in list view (e.g., "1a", "1b" for same priority)

**Recommendation:** Option 1 (warn but allow)

---

## 8.2 In-Memory vs Persistent Simulation State

**Question:** Should simulation inputs be persisted between app sessions?

**Options:**
1. **In-memory only** (Recommended for Phase 4)
   - Simulation state is reset on app restart
   - Simpler implementation
2. **Persist to JSON**
   - Save last simulation inputs to `simulation-state.json`
   - Resume testing where user left off

**Recommendation:** Option 1 (in-memory only) for Phase 4. Persistence can be added in Phase 5 if needed.

---

## 8.3 Real-Time Constraint Reload

**Question:** Should the app detect changes to `policy-constraints.json` and reload automatically?

**Options:**
1. **Manual reload only** (Recommended for Phase 4)
   - User must press "Reload" button or restart app
2. **File system watcher**
   - Use `FileManager` or `DispatchSource` to watch for file changes
   - Auto-reload when file is modified externally

**Recommendation:** Option 1 (manual reload) for Phase 4. File watching can be added in Phase 5 if needed.

---

## 8.4 Error Handling for PolicyEngine.evaluate() in Production

**Question:** What should happen if PolicyEngine throws an error in production (not simulation)?

**Current Behavior (Section 3.7):**
- PolicyEngine throws `RoutingError.policyViolation` if a constraint blocks execution
- Router catches this and propagates to ExecutionCoordinator

**Options for Constraint Editor:**
1. **Display error in simulation** (Current design)
   - Simulation mode catches and displays error message
2. **Production error UI** (Future phase)
   - If PolicyEngine throws in production, show user-friendly error dialog with trace_id

**Recommendation:** Option 1 for Phase 4 (simulation only). Production error UI is part of Phase 5 (Execution Visibility).

---

# SECTION 9 — Summary

## 9.1 Key Design Decisions

1. **Developer-Facing UI** — Phase 4 targets developers (macOS only), not end-users
2. **JSON Persistence** — Constraints stored in Application Support directory
3. **Separate Editable Model** — `EditablePolicyRule` decouples UI from domain model
4. **Simulation Mode** — Test policy evaluation before production deployment
5. **Determinism Verification** — Built-in 10x test to verify PolicyEngine purity
6. **AppSettings Integration** — Constraints loaded into shared state on startup
7. **No PolicyEngine Modification** — Engine remains pure and UI-independent

---

## 9.2 Architectural Compliance

| Design Requirement | Compliance Status |
|--------------------|-------------------|
| PolicyEngine remains pure | ✅ YES — No UI dependencies |
| Router is not modified | ✅ YES — No changes to Router.swift |
| Determinism is maintained | ✅ YES — Simulation mode verifies this |
| Constraints are testable | ✅ YES — Simulation mode provides testing |
| UI is stateful, engine is not | ✅ YES — Clear separation of concerns |
| Persistence is JSON-based | ✅ YES — Application Support directory |
| Integration with production flow | ✅ YES — Via AppSettings.shared.policyRules |

---

## 9.3 Phase 4 Deliverables

1. **Code**
   - `EditablePolicyRule.swift` (domain model)
   - `ConstraintStore.swift` (persistence)
   - `ConstraintEditorViewModel.swift` (business logic)
   - `SimulationViewModel.swift` (testing logic)
   - `ConstraintEditorView.swift` (UI)
   - `SimulationView.swift` (UI)
   - Unit tests + UI tests

2. **Documentation**
   - This design document
   - Constraint JSON schema README
   - Inline code comments

3. **Integration**
   - `AppSettings` update to include `policyRules`
   - Execution coordinator integration
   - End-to-end integration test

---

## 9.4 Next Steps (Post-Phase 4)

1. **Phase 5: Execution Visibility**
   - Integrate Constraint Editor with execution history
   - Display triggered constraints in past executions
   - Show trace IDs in simulation mode

2. **Phase 6: End-User UI**
   - Port Constraint Editor to iOS/iPadOS
   - Simplify UI for non-technical users
   - Add constraint templates library

3. **Phase 7: Advanced Features**
   - Constraint import/export
   - Cloud sync
   - Advanced condition operators (regex, OR logic)
   - Rule provenance tracking

---

## Appendix A — Example Constraint JSON

```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "name": "Block Sensitive Data",
    "type": "privacy",
    "enabled": true,
    "priority": 1,
    "conditions": [
      {
        "field": "content",
        "operator": "contains",
        "value": "SSN|credit card|password"
      }
    ],
    "action": {
      "type": "block",
      "reason": "Prompt contains sensitive data patterns"
    }
  },
  {
    "id": "550e8400-e29b-41d4-a716-446655440001",
    "name": "Force Local for Personal Queries",
    "type": "privacy",
    "enabled": true,
    "priority": 2,
    "conditions": [
      {
        "field": "content",
        "operator": "contains",
        "value": "my|I am|personal|private"
      }
    ],
    "action": {
      "type": "forceLocal"
    }
  },
  {
    "id": "550e8400-e29b-41d4-a716-446655440002",
    "name": "Warn on Large Queries",
    "type": "cost",
    "enabled": true,
    "priority": 3,
    "conditions": [
      {
        "field": "token_count",
        "operator": "exceeds",
        "value": "5000"
      }
    ],
    "action": {
      "type": "warn",
      "message": "This query is large and may incur cloud costs"
    }
  },
  {
    "id": "550e8400-e29b-41d4-a716-446655440003",
    "name": "Require Confirmation for Cloud Analytical Queries",
    "type": "cost",
    "enabled": false,
    "priority": 4,
    "conditions": [
      {
        "field": "intent",
        "operator": "equals",
        "value": "analytical"
      },
      {
        "field": "privacy_level",
        "operator": "equals",
        "value": "auto"
      }
    ],
    "action": {
      "type": "requireConfirmation",
      "prompt": "Analytical queries use cloud models. Proceed?"
    }
  }
]
```

---

## Appendix B — Codable Conformance for ConstraintAction

To support JSON encoding/decoding of `ConstraintAction`, we need custom Codable implementation:

```swift
extension ConstraintAction: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case reason
        case prompt
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "block":
            let reason = try container.decode(String.self, forKey: .reason)
            self = .block(reason: reason)
        case "forceLocal":
            self = .forceLocal
        case "forceCloud":
            self = .forceCloud
        case "requireConfirmation":
            let prompt = try container.decode(String.self, forKey: .prompt)
            self = .requireConfirmation(prompt: prompt)
        case "warn":
            let message = try container.decode(String.self, forKey: .message)
            self = .warn(message: message)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown action type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .block(let reason):
            try container.encode("block", forKey: .type)
            try container.encode(reason, forKey: .reason)
        case .forceLocal:
            try container.encode("forceLocal", forKey: .type)
        case .forceCloud:
            try container.encode("forceCloud", forKey: .type)
        case .requireConfirmation(let prompt):
            try container.encode("requireConfirmation", forKey: .type)
            try container.encode(prompt, forKey: .prompt)
        case .warn(let message):
            try container.encode("warn", forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}
```

---

**End of Document**
