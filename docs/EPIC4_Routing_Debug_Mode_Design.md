# EPIC4 Issue #70 — Routing Debug Mode: Design Document

- **Issue**: #70 (sub-issue of EPIC #57 — Routing & Hybrid Execution)
- **Status**: Draft — pending Taka review
- **Date**: 2026-05-15
- **Author**: Claude (Sonnet 4.6) via MCP
- **Predecessor**: #68 PolicyEngine Extensibility (merged PR #77)
- **Next**: #69 Human Override Mechanism

---

## 1. Background

### 1.1 EPIC4 DoD における #70 の位置付け

EPIC4 (Issue #57) の残作業順序は Max により確定済み:

```
✅ #68 PolicyEngine extensibility  (PR #75, #76, #77 — merged)
→  #70 Routing debug mode          ← 本 design の対象
→  #69 Human override mechanism
```

### 1.2 現状の Tracing インフラ（PR #66, #67 で landed）

`Shared/Runtime/Tracing/` に既存実装:

| ファイル | 役割 | 現状の限界 |
|---|---|---|
| `ExecutionTrace.swift` | 1回の実行全体のメタデータ | routing フィールドは `RoutingTrace?` だが最小限 |
| `RoutingTrace.swift` | ルーティング決定のキャプチャ | `ruleId`, `decision`, `duration`, `decisionReason` のみ |
| `PolicyTrace.swift` | ポリシー評価のキャプチャ | 最小実装 |
| `TraceCollector.swift` | actor-based thread-safe ストレージ | in-memory only |
| `FileTraceSink.swift` | 永続化 | 存在するが routing step ごとの詳細なし |
| `TraceDebugPrinter.swift` | 人間可読 print | route/error でフィルタのみ、step-by-step なし |

### 1.3 現状の Router.swift の構造

`Router.route()` は 4 step の pure function:

```
STEP 1: Policy Decision Engine Result 適用
STEP 2: Privacy Guarantee 強制
STEP 3: Auto Mode Logic (3.1〜3.4)
STEP 4: Fallback (ExecutionCoordinator 側)
```

**問題**: どの STEP で決定が下されたか、なぜその STEP に到達したか、各 STEP の入力値が何だったかが現状トレースに記録されていない。

---

## 2. Issue #70 のスコープ

Issue #70 の DoD: "routing log 強化、override trace"

本 design が扱うもの:
- Router の 4 step 各々の decision point を trace に記録
- `RoutingTrace` の情報量を強化（step-level detail）
- debug mode フラグで詳細ログの on/off を制御
- `TraceDebugPrinter` の強化（step-by-step 可読出力）

**明示的に OUT OF SCOPE（Max NG ライン）**:
- hot-reload
- agent autonomy 系の動作変更
- `Router.swift` の purity contract の破壊（side-effect の導入）
- async への変更

---

## 3. 設計方針

### 3.1 Router の purity contract は絶対に守る

`Router.route()` はこれまで通り pure function のまま。debug 情報の収集を Router 内部で行うことは **しない**。

代わりに、Router が `RoutingDecision` に加えて **`RoutingStepTrace`** を返すオーバーロードを追加する。呼び出し側（`ExecutionCoordinator`）が debug mode 時のみこれを呼ぶ。

### 3.2 アーキテクチャ: step trace の流れ

```
ExecutionCoordinator.execute()
    │
    ├─ [normal mode]
    │       Router.route(question:runtimeState:policyResult:)
    │       → RoutingDecision
    │
    └─ [debug mode]
            Router.routeWithTrace(question:runtimeState:policyResult:)
            → (RoutingDecision, RoutingStepTrace)
            RoutingStepTrace → ExecutionTrace.routing に格納
            FileTraceSink → 永続化
```

Router の 2 つの entry point:
- `route(...)` — 既存、変更なし、production path
- `routeWithTrace(...)` — 新規、debug path のみ使用、同じ決定ロジックを内部で呼ぶ

### 3.3 RoutingStepTrace の構造

```swift
// New type: Shared/Runtime/Tracing/RoutingStepTrace.swift
struct RoutingStepTrace: Codable {
    // Which step terminated the routing
    let terminatingStep: RoutingStep

    // Per-step records (only steps actually evaluated)
    let steps: [RoutingStepRecord]

    // Inputs visible at routing time
    let inputSnapshot: RoutingInputSnapshot
}

enum RoutingStep: String, Codable {
    case policyEnforcement  // STEP 1
    case privacyEnforcement // STEP 2
    case autoModeLogic      // STEP 3
}

struct RoutingStepRecord: Codable {
    let step: RoutingStep
    let outcome: RoutingStepOutcome
    let detail: String  // human-readable, e.g. "forceLocal → POLICY_FORCE_LOCAL"
}

enum RoutingStepOutcome: String, Codable {
    case passedThrough  // step evaluated, did not terminate routing
    case terminated     // step produced the final RoutingDecision
    case threw          // step threw RoutingError
}

struct RoutingInputSnapshot: Codable {
    let privacyLevel: String
    let networkState: String
    let tokenCount: Int
    let tokenThreshold: Int
    let localModelAvailable: Bool
    let intentSupportedLocally: Bool
    let policyEffectiveAction: String
}
```

### 3.4 debug mode フラグ

`RuntimeState` に `debugMode: Bool` を追加（デフォルト `false`）。

```swift
// RuntimeState.swift への追加
struct RuntimeState: Equatable {
    // ... 既存フィールド ...
    let debugMode: Bool  // default: false
}
```

`ExecutionCoordinator` が `runtimeState.debugMode` を見て、`routeWithTrace` を呼ぶかどうかを判断する。

**Max NG ライン確認**: `debugMode` は行動変更ではなく observability の on/off のみ。routing 結果自体は変わらない。これは agent autonomy の変更ではないため NG ラインに抵触しない。

### 3.5 TraceDebugPrinter の強化

既存の `printTrace()` を拡張して、`RoutingStepTrace` が存在する場合に step-by-step 出力を追加:

```
[14:32:01] route=local duration=0.003s
query="What is the capital of France?"
[STEP 1 - Policy]  passedThrough: action=allow
[STEP 2 - Privacy] passedThrough: level=auto
[STEP 3 - Auto]    terminated: tokens=7 ≤ threshold=4096, localAvail=true, intentOK=true → local
```

---

## 4. 実装計画（3 Phase）

### Phase 1: 型定義
- `Shared/Runtime/Tracing/RoutingStepTrace.swift` — 新規作成
- `Shared/Routing/RuntimeState.swift` — `debugMode: Bool` 追加
- テスト: `RoutingStepTrace` の Codable round-trip

### Phase 2: Router.routeWithTrace()
- `Shared/Routing/Router.swift` — `routeWithTrace()` 追加（既存 `route()` は無変更）
- `Shared/Runtime/Execution/ExecutionCoordinator.swift` — debug mode 分岐追加
- `Shared/Runtime/Tracing/ExecutionTrace.swift` — `routingSteps: RoutingStepTrace?` フィールド追加
- テスト: 各 STEP termination パターン（6 ケース）

### Phase 3: TraceDebugPrinter 強化
- `Shared/Runtime/Tracing/TraceDebugPrinter.swift` — step-level 出力追加
- テスト: `printTrace()` の出力文字列アサーション

---

## 5. 後方互換性

- `RuntimeState` の `debugMode` はデフォルト `false` → 既存コードの変更不要
- `ExecutionTrace` の `routingSteps` は `Optional` → 既存 JSON decode は壊れない
- `Router.route()` のシグネチャ変更なし → 既存 call site 変更不要
- 既存テスト（`RouterDeterminismTests`, `PolicyEngineTests`, `ExecutionCoordinatorTests`）はすべて pass without modification

---

## 6. 確認事項（Taka review 用）

1. `RuntimeState.debugMode` の追加は許容範囲か（or 別の injection 方法が好ましいか）
2. `routeWithTrace()` を Router の static method として追加するアプローチでよいか
3. Phase 分割（1→2→3）の粒度は適切か
4. `RoutingInputSnapshot` にキャプチャすべき追加フィールドはあるか
