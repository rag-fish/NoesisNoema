# EPIC4 Issue #69 — Human Override Mechanism: Design Document

- **Issue**: #69 (sub-issue of EPIC #57 — Routing & Hybrid Execution)
- **Status**: Draft — pending Taka review
- **Date**: 2026-05-15
- **Author**: Claude (Sonnet 4.6) via MCP
- **Predecessor**: #70 Routing Debug Mode (merged PR #78)
- **Completes**: EPIC4 DoD condition 3 — "Human override possible"

---

## 1. Background

### 1.1 EPIC4 DoD における #69 の位置付け

```
✅ #68 PolicyEngine extensibility  (PR #75–77)
✅ #70 Routing debug mode          (PR #78)
→  #69 Human override mechanism   ← 本 design の対象 (EPIC4 最終)
```

これが完成すれば EPIC4 DoD の全3条件が揃い、EPIC4 close 可能。

### 1.2 #70 で用意された接続点

#70 で以下が main に landed 済み:

- `RoutingInputSnapshot.overrideMode: String?` — future-ready フィールド (現在 nil)
- `NoemaQuestion.toolRequired / privacySensitive / lowLatencyPreferred` — routing signal first-class fields
- `Router._evaluate()` が `RoutingInputSnapshot` を構築する単一箇所
- `HybridExecutionCoordinator.buildQuestion(from:)` — question 構築の単一箇所

### 1.3 Issue #69 の DoD

元の issue 記述: `forceLocal / forceRemote` + `debug flag` + `UI or API injection`

`debug flag` は #70 で `RuntimeState.debugMode` として実装済み。
本 issue の実装対象:
- `forceLocal / forceRemote` override
- UI or API injection (= `HybridExecutionCoordinator` 経由の注入)

---

## 2. 設計方針

### 2.1 Override は PolicyAction として表現する

既存の `PolicyAction` enum はすでに `.forceLocal` / `.forceCloud` を持っている。
Router の STEP 1 はこれを最高優先度で処理する。

つまり **Human override の本質は「最高優先度の PolicyEvaluationResult を注入すること」**。
新しいルーティングロジックは不要。

```
HumanOverride.forceLocal
  → PolicyEvaluationResult(effectiveAction: .forceLocal)
  → Router STEP 1 で即座に終了
  → RoutingDecision(routeTarget: .local, ruleId: .POLICY_FORCE_LOCAL)
```

### 2.2 OverrideMode — 値型で表現

```swift
// 新規: Shared/Routing/HumanOverrideMode.swift
enum HumanOverrideMode: String, Codable, Equatable {
    case forceLocal   // Force local regardless of policy/privacy/auto logic
    case forceRemote  // Force cloud regardless of policy/privacy/auto logic
    case none         // No override; normal routing applies
}
```

`none` を明示的に持つことで Optional を使わず、
call site での nil チェックを排除する。

### 2.3 RuntimeState への追加

```swift
// RuntimeState.swift に追加
let overrideMode: HumanOverrideMode  // default: .none
```

`HybridExecutionCoordinator.buildRuntimeState()` が
このフィールドを注入する唯一の箇所になる。

### 2.4 HybridExecutionCoordinator への注入口

Max NG ライン「agent autonomy の変更禁止」を考慮し、
override は **Coordinator の外から渡される値** として設計する。
Coordinator が自律的に override を決定することはない。

```swift
// HybridExecutionCoordinator
func execute(request: NoemaRequest, overrideMode: HumanOverrideMode = .none) async throws -> NoemaResponse
```

call site (UI / API layer) が `overrideMode` を渡す。
Coordinator は受け取った値を `RuntimeState` に乗せるだけ。

### 2.5 Override → PolicyEvaluationResult への変換

`buildRuntimeState()` ではなく、PolicyEngine 評価後に override を適用する。
理由: override は policy rule より強い最上位の意図であり、
rule evaluation の結果を上書きするのが正しいセマンティクス。

```swift
// HybridExecutionCoordinator.execute() 内の flow
let basePolicyResult = try PolicyEngine.evaluate(question:runtimeState:rules:)
let policyResult = applyOverride(basePolicyResult, override: overrideMode)
// → Router.route(question:runtimeState:policyResult:) へ
```

```swift
private func applyOverride(
    _ base: PolicyEvaluationResult,
    override mode: HumanOverrideMode
) -> PolicyEvaluationResult {
    switch mode {
    case .none:
        return base
    case .forceLocal:
        return PolicyEvaluationResult(
            effectiveAction: .forceLocal,
            appliedConstraints: base.appliedConstraints,
            warnings: base.warnings,
            requiresConfirmation: false
        )
    case .forceRemote:
        return PolicyEvaluationResult(
            effectiveAction: .forceCloud,
            appliedConstraints: base.appliedConstraints,
            warnings: base.warnings,
            requiresConfirmation: false
        )
    }
}
```

### 2.6 RoutingInputSnapshot.overrideMode の充填

#70 で `overrideMode: String?` を future-ready として追加済み。
本 issue で `HumanOverrideMode.rawValue` を渡して充填する。

```swift
// Router._evaluate() 内 inputSnapshot 構築
overrideMode: runtimeState.overrideMode == .none ? nil : runtimeState.overrideMode.rawValue
```

---

## 3. 実装ファイル一覧 (2 Phase)

### Phase 1: 型定義と RuntimeState 拡張

| ファイル | 変更内容 |
|---|---|
| `Shared/Routing/HumanOverrideMode.swift` | **新規**: `HumanOverrideMode` enum |
| `Shared/Routing/RuntimeState.swift` | `overrideMode: HumanOverrideMode` 追加 (default `.none`) |

### Phase 2: Coordinator 統合

| ファイル | 変更内容 |
|---|---|
| `Shared/Runtime/Execution/HybridExecutionCoordinator.swift` | `execute(request:overrideMode:)` 引数追加、`applyOverride()` 追加、`buildRuntimeState()` に `overrideMode` 注入、`RoutingInputSnapshot.overrideMode` 充填 |
| `Shared/Routing/Router.swift` | `_evaluate()` 内 `inputSnapshot.overrideMode` を `runtimeState.overrideMode` から充填 |

---

## 4. 後方互換性

- `execute(request:overrideMode:)` の `overrideMode` は default `.none` → 既存 call site 変更不要
- `RuntimeState.overrideMode` は default `.none` → 既存 initializer call site 変更不要
- Router の routing logic は変更なし — override は PolicyEvaluationResult を通じて STEP 1 で処理
- 既存テスト (RouterDeterminismTests / PolicyEngineTests / ExecutionCoordinatorTests) は pass without modification

---

## 5. 明示的 OUT OF SCOPE

- UI コンポーネント (override トグル UI) — #69 は API layer まで
- override の永続化 (UserDefaults / ConstraintStore への保存)
- override の audit log / trace への専用フィールド追加 (`RoutingInputSnapshot.overrideMode` で十分)
- agent autonomy による override の自動設定

---

## 6. 確認事項 (Taka review 用)

1. `execute(request:overrideMode:)` のシグネチャ追加アプローチで OK か
   (alternative: override を `NoemaRequest` に持たせる)
2. `applyOverride()` が PolicyEngine 結果を上書きするセマンティクスで OK か
   (alternative: override を STEP 0 として Router に追加する)
3. Phase 分割 (1 型定義 → 2 Coordinator 統合) の粒度は適切か
