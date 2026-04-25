# EPIC4 — PolicyEngine Extensibility Design

## 1. Author / Status / Date

- **Authors**: Taka, Claude (Opus 4.7)
- **Predecessor work**: Initial PolicyEngine implementation by Claude (Sonnet 4.6) via GitHub Copilot
- **Reviewer / Adjudicator**: Taka
- **Status**: Draft — pending review
- **Date**: 2026-04-25
- **Issue**: #68 (sub-issue of EPIC #57 — Routing & Hybrid Execution)

---

## 2. Background

### 2.1 EPIC4 における #68 の位置付け

EPIC4 (Issue #57) の Definition of Done は 3 条件:

1. Local vs cloud router implemented ✅ (PR #61, #62, #63 で main へ landed)
2. Policy-based switching ⚠️ (基礎は landed、構造的な extensibility は未対応 ← **本 design の対象**)
3. Human override possible ❌ (#69 で扱う)

EPIC4 残作業の 3 つの sub-issue (#68, #70, #69) は **#68 → #70 → #69 の順** で着手する。本 design は #68 のためのもの。

### 2.2 現状の PolicyEngine 実装の構造監査

現状の実装(`Shared/Policy/` 配下の 4 core file)は、deterministic な評価という point では完成度が高い:

- `PolicyRule` は `Codable`、`id` / `name` / `type` / `enabled` / `priority` / `conditions` / `action` を持つ struct
- `PolicyEngine.evaluate()` は pure function、4-step algorithm (filter → sort → evaluate → resolve) を厳格に踏む
- Precedence hierarchy (`BLOCK > FORCE_LOCAL > FORCE_CLOUD > REQUIRE_CONFIRMATION > WARN`) は明示的に実装されている
- 永続化は `ConstraintStore` が JSON file (`policy-constraints.json`) で graceful degradation 付きに行う
- `EditablePolicyRule` が UI 側のための mutable counterpart を提供

しかし、構造的な extensibility の観点では弱点がある。`PolicyEngine.swift` の core にある条件評価は、依然として **switch 連鎖** に依存している:

```swift
// PolicyEngine.swift, evaluateCondition より抜粋 (現状)
switch condition.field {
case "content":       return evaluateStringCondition(condition, value: question.content)
case "token_count":   return evaluateNumericCondition(condition, value: estimateTokenCount(question.content))
case "intent":        return evaluateStringCondition(condition, value: intent.rawValue)
case "privacy_level": return evaluateStringCondition(condition, value: question.privacyLevel.rawValue)
default:              return false
}
```

そして operator 側にも同じ pattern がある:

```swift
switch condition.operator {
case .contains:    /* ... */
case .notContains: /* ... */
case .equals:      /* ... */
default:           return false
}
```

この構造の含意は次の通り:

- **新しい condition field を追加するには `PolicyEngine.swift` を編集する必要がある** — 現状では新しい input source (例: `time_of_day`、`connectivity`、`model_capability`) を rule で表現したくなった瞬間、core engine に手を入れざるを得ない
- **新しい operator を追加する場合も同様** — 比較ロジックが engine 内 switch にハードコードされているため、追加点が分散する
- **Rule は data 化されているが、評価軸は code に閉じている** — つまり「rule を data として持つ」という ADR-0005 の意図のうち、**rule の構造** は満たしているが、**評価の構造** は満たし切れていない

### 2.3 Issue #68 DoD の真の意味

Issue #68 は表面的には "rule abstraction、config 化、trace-driven rule" と書かれているが、これらを features として個別に実装する方向は本 design の scope ではない (`5. Alternatives Considered` 参照)。

#68 の真の意味は次の一文に集約される:

> **PolicyEngine を "機能" ではなく "構造" に昇格させる。**

具体的には:

- **rules must be composable** — 新しい rule の追加が既存 rule の修正なしに可能であること
- **inputs must be explicit** — Engine が何を input として受け取るかが contract として明示されていること
- **outputs must be deterministic** — 同じ input に対して同じ output が常に返ること (現状維持)
- **structure must support future evolution** — 新 condition / 新 operator / 新 action の追加が core engine の編集なしに可能であること

これは ADR-0005 の "Policy expressed as data rather than code" の最も忠実な解釈であり、ADR-0000 の Constitutional Constraint #2 (Routing Authority Locality) および #6 (Model Neutrality) と整合する。

---

## 3. Goals & Non-Goals

### 3.1 Goals

| Goal | 達成基準 |
|---|---|
| **G1. Composable rules** | 新 condition を追加する際、`PolicyEngine.swift` を編集しないで済む |
| **G2. Explicit inputs** | Engine の input が型で明示されており、何が必要・何が optional かが contract として読める |
| **G3. Deterministic outputs** | 同じ `(question, runtimeState, rules)` に対して常に同じ `PolicyEvaluationResult` を返す (現状維持) |
| **G4. Future evolution support** | 新 operator / 新 action 追加時の修正範囲が局所化される |
| **G5. Routing からの完全分離** | `Shared/Routing/` への依存を PolicyEngine が一切持たない |
| **G6. Backward compatibility** | 既存の `policy-constraints.json` ファイルが migration なしで読み込める |
| **G7. Existing tests pass** | `PolicyEngineTests`、`ConstraintPersistenceTests`、`RouterDeterminismTests` が全 pass |

### 3.2 Non-Goals

| Non-Goal | 理由 |
|---|---|
| 評価アルゴリズムの変更 | 4-step (filter → sort → evaluate → resolve) は十分、変える理由がない |
| Precedence hierarchy の変更 | `BLOCK > FORCE_LOCAL > FORCE_CLOUD > REQUIRE_CONFIRMATION > WARN` は ADR-0006 の Authority Model に基づく、本 design では維持 |
| hot-reload の実装 | observability / configuration layer の話、別 sub-issue (もしくは別 EPIC) で扱う |
| Trace integration の中心化 | 同上、observability layer の責務 |
| Provenance tracking の追加 | 同上 |
| ConstraintEditorView の大規模刷新 | UI は本 design の scope 外 |
| 新 condition / operator / action の実装 | 拡張可能性の **証明** として 1 個だけ追加 (`7.4 Phase 4`)、実用的な追加は別途 |
| Routing logic の変更 | #69 (Human override) と #70 (Routing debug) で扱う |
| Async 化 | 現状 sync の決定性を保つ、Max からの明示的 NG line |

---

## 4. Proposal

### 4.1 Condition を Swift protocol に lift

現状の `ConditionRule { field: String, operator: Operator, value: String }` は、**string で識別される generic data**。これを protocol-based の **構造** に置き換える:

```swift
/// 各 condition は自分自身の評価責任を持つ。
/// PolicyEngine は条件の中身を知らない。
protocol ConditionEvaluator {
    /// 同期的・決定的に評価する。
    /// - Parameters:
    ///   - question: 評価対象の質問
    ///   - runtimeState: 現在のランタイム状態
    /// - Returns: 条件が満たされていれば true
    func evaluate(question: NoemaQuestion, runtimeState: RuntimeState) -> Bool
}
```

既存の 4 つの field (`content`、`token_count`、`intent`、`privacy_level`) はそれぞれ concrete struct として実装される:

```swift
struct ContentCondition: ConditionEvaluator { 
    let matcher: StringMatcher
    let pattern: String
    func evaluate(...) -> Bool { /* ... */ }
}

struct TokenCountCondition: ConditionEvaluator {
    let comparator: NumericComparator
    let threshold: Int
    func evaluate(...) -> Bool { /* ... */ }
}

// IntentCondition, PrivacyLevelCondition も同様
```

これにより:

- 新しい input source (例: `TimeOfDayCondition`、`ConnectivityCondition`) は **新しい struct を 1 個書くだけ**で追加可能
- `PolicyEngine.swift` は **新 condition を知らないまま動く**
- 既存の switch 連鎖は消える

### 4.2 Operator を value-typed strategy として表現

現状の `Operator` enum + Engine 内 switch は、比較 strategy struct に閉じる:

```swift
struct StringMatcher {
    enum Mode { case contains, notContains, equals, notEquals }
    let mode: Mode
    func matches(_ candidate: String, against pattern: String) -> Bool { /* ... */ }
}

struct NumericComparator {
    enum Mode { case exceeds, lessThan, equals, notEquals }
    let mode: Mode
    func matches(_ candidate: Int, against threshold: Int) -> Bool { /* ... */ }
}
```

将来的に新 operator (例: `regex`、`fuzzyMatch`) を追加したくなった場合、**比較 strategy 側の追加で完結**する。Condition 側は新 strategy を hold するだけ。

### 4.3 PolicyRule の構造再定義

既存の `PolicyRule` の **対外的な性質は維持** する:

- struct であること
- `Codable` であること
- `id` / `name` / `type` / `enabled` / `priority` / `action` の field を持つこと

変更点は内部の `conditions` 表現のみ。`[ConditionRule]` から **`[any ConditionEvaluator]`** へ移行する (Swift 5.7+ の existential)。

```swift
struct PolicyRule: Identifiable {
    let id: UUID
    let name: String
    let type: ConstraintType
    let enabled: Bool
    let priority: Int
    let conditions: [any ConditionEvaluator]  // ← changed
    let action: ConstraintAction
    
    /// 全 condition が AND で満たされていれば true。
    /// PolicyEngine から呼ばれる。
    func evaluate(question: NoemaQuestion, runtimeState: RuntimeState) -> Bool {
        conditions.allSatisfy { $0.evaluate(question: question, runtimeState: runtimeState) }
    }
}
```

評価責任が `PolicyEngine` から `PolicyRule` へ、さらに各 `ConditionEvaluator` へと **段階的に局所化** されている点に注目してほしい。これが Max のガイダンス「rule は struct として持つ、evaluation は同期的・決定的」の最も直截な表現。

### 4.4 PolicyEngine = pure orchestrator

`PolicyEngine` は **何も決めない、何も知らない、ただ並べて結果をまとめるだけ** になる:

```swift
struct PolicyEngine {
    static func evaluate(
        question: NoemaQuestion,
        runtimeState: RuntimeState,
        rules: [PolicyRule]
    ) throws -> PolicyEvaluationResult {
        // STEP 1: filter
        let active = rules.filter { $0.enabled }
        
        // STEP 2: sort (priority, id)
        let sorted = active.sorted { /* same as current */ }
        
        // STEP 3: evaluate (DELEGATED to each rule)
        let matched = sorted.filter { $0.evaluate(question: question, runtimeState: runtimeState) }
        
        // STEP 4: resolve conflicts (precedence hierarchy)
        return try resolveConflicts(matched: matched)  // unchanged
    }
}
```

新 condition / operator / action の追加で **このコードは 1 行も変わらない**。これが extensibility の構造的な証明。

### 4.5 Routing からの完全分離

PolicyEngine の input/output:

- **Input**: `NoemaQuestion`、`RuntimeState`、`[PolicyRule]` のみ
- **Output**: `PolicyEvaluationResult` のみ
- **PolicyEngine が触れない型**: `RoutingDecision`、`RoutingError`、`Router`、`RoutingTrace`、`ExecutionTrace`、その他 `Shared/Routing/` 配下のすべて

`Shared/Policy/` から `Shared/Routing/` への import 文を **本 design 完了時点で 0 にする** ことを CI で確認可能にする (実装フェーズで grep ベースのテストを追加)。

これは Max の NG line「routing とは完全分離」の implementation 上の表現。

### 4.6 既存永続化との互換性

`policy-constraints.json` の serialized form は **そのまま読める** ことを保証する。

現状の JSON は次の shape:

```json
[
  {
    "id": "...",
    "name": "...",
    "conditions": [
      { "field": "content", "operator": "contains", "value": "SSN|password" }
    ],
    "action": { "block": { "reason": "..." } }
  }
]
```

protocol-based 構造に移行した後も、この JSON 表現は維持される。Decoder が `field` の文字列を見て対応する concrete `ConditionEvaluator` (例: `ContentCondition`) に dispatch する。これは既存の field/operator/value の string-based identifier を **discriminator** として再利用する形であり、**migration を必要としない**。

これは「rule を data 化しすぎない」という Max の NG line に対する明示的な対応。**永続化は data 表現が必要、しかし engine 内部の構造は Swift type system で表現する** — 両者は別レイヤーであり、本 design では engine 内部のみ struct/protocol 化する。

詳細な Codable 戦略 (tagged enum か type discriminator か) は実装フェーズの判断事項とし、本 design では「現行 JSON が読める」ことのみを契約する。

---

## 5. Alternatives Considered

### 5.1 Rule DSL 言語の導入

外部 DSL (例: Rego、CEL、独自 mini-language) で rule を表現する案。

**Rejected.** 理由:

- ADR-0000 (Constitutional Constraint #3: Decision Transparency) に対して、外部 DSL は監査可能性を悪化させる
- 既存 codebase は Swift 一本で完結しており、DSL parser / evaluator の追加は依存と複雑性を持ち込む
- 「rule をデータ化しすぎ」という Max の NG line に正面衝突する
- Swift の type system で十分に表現できる

### 5.2 PolicyEngine を pluggable strategy 化

`PolicyEngine` 自体を protocol にし、複数の実装を差し替え可能にする案。

**Rejected.** 理由:

- 1 つの NoesisNoema instance に 1 つの policy engine で十分。複数実装を持つ要件がない
- ADR-0006 (Contract Lock) の deterministic boundary 思想に対して、engine の差し替え可能性は contract をぼかす
- 必要になった瞬間に単純に追加可能 (現状の決定が将来を縛らない)

### 5.3 Condition を data-only enum に保つ

現状の `ConditionRule { field, operator, value }` を維持し、Engine 側に field 追加の switch case を増やしていく案。

**Rejected.** 理由:

- そもそもこれが #68 の解決対象 (現状の構造そのもの)
- 拡張性ゼロ、Max ガイダンスに正面衝突

### 5.4 hot-reload を #68 に内包する

policy-constraints.json の変更を runtime で再 load する機能を本 design に含める案。

**Rejected.** 理由:

- Max の明示的な NG line: 「hot-reload 中心に設計するな」
- これは observability / configuration layer の話、PolicyEngine の core 責務ではない
- 現行の `PolicyRulesProvider.notifyRulesUpdated()` の no-op コメント「Future Hook」は将来の拡張点として残すが、本 design では触らない

### 5.5 Trace を PolicyEngine の core 責務に組み込む

PolicyEngine の output に常に trace metadata を含める、もしくは PolicyEngine が `TraceCollector` に直接 emit する案。

**Rejected.** 理由:

- Max の NG line:「trace ベースにするな」
- Trace は cross-cutting concern、PolicyEngine が知るべきことではない
- 本 design では PolicyEngine の output (`PolicyEvaluationResult`) が trace 用に必要十分な情報を含む形を維持し、trace 統合は呼び出し側の責任とする

---

## 6. Impact

### 6.1 既存 file への変更

| File | 変更の性質 |
|---|---|
| `Shared/Policy/PolicyRule.swift` | `conditions` field の型変更 (`[ConditionRule]` → `[any ConditionEvaluator]`)、`evaluate()` method 追加 |
| `Shared/Policy/PolicyEngine.swift` | switch 連鎖の削除、4-step orchestration のみ残す。`evaluateCondition` / `evaluateStringCondition` / `evaluateNumericCondition` / `estimateTokenCount` 等の private helper は概念的に対応する Condition struct へ移譲 |
| `Shared/Policy/EditablePolicyRule.swift` | UI 用 mutable model の更新。新 protocol-based 構造に対して bidirectional 変換を維持 |
| `Shared/Policy/ConstraintStore.swift` | Codable 戦略の更新 (tagged form もしくは discriminator) で既存 JSON との互換維持 |
| `Shared/Policy/ConstraintEditorView.swift` 等 UI | **触らない** — UI は `EditablePolicyRule` 経由のため、その境界より下の変更で吸収 |

### 6.2 新規 file (想定)

```
Shared/Policy/
├── Conditions/
│   ├── ConditionEvaluator.swift          (protocol)
│   ├── ContentCondition.swift
│   ├── TokenCountCondition.swift
│   ├── IntentCondition.swift
│   └── PrivacyLevelCondition.swift
└── Operators/
    ├── StringMatcher.swift
    └── NumericComparator.swift
```

サブディレクトリ名は実装フェーズで confirm。本 design では「`Conditions/` と `Operators/` のような責務別 grouping」までを明示し、具体名は変動可。

### 6.3 ADR への compliance

| ADR | 関連箇所 | 本 design との整合 |
|---|---|---|
| ADR-0000 | Constraint #2 (Routing Authority Locality), #3 (Decision Transparency), #6 (Model Neutrality), Anti-pattern #3 (Opaque Routing) | ✅ Decision logic が client 内に局所化、評価は決定的、新 condition の追加でも transparency 維持 |
| ADR-0004 | Decision/Execution/Knowledge layer separation | ✅ PolicyEngine は Decision layer 内部の構造化、layer boundary に touch しない |
| ADR-0005 | "Policy expressed as data rather than code" mitigation | ✅ Rule structure を Swift type system で **data として表現する** 形を取る (本 design はこの ADR の最も直截な実装) |
| ADR-0006 | Contract Lock (4 contracts at v1.0.0) | ✅ Invocation Boundary、API Schema、Constraint Contract、Authority Model のいずれも touch しない。本 design は internal restructuring のみ |
| ADR-0007 | Integration Boundary | ✅ External Client から見た PolicyEngine の振る舞いは無変更 |

### 6.4 Test strategy

- **Existing tests must pass without modification**:
  - `PolicyEngineTests/PolicyEngineTests.swift`
  - `PolicyEngineTests/ConstraintPersistenceTests.swift`
  - `RouterTests/RouterDeterminismTests.swift`
  - `ExecutionCoordinatorTests/ExecutionCoordinatorTests.swift`

- **New tests**:
  - `ConditionEvaluator` protocol 適合性 — 各 concrete struct が protocol を満たすことの compile-time チェック
  - Extensibility proof — `7.4 Phase 4` で追加する 1 個の新 condition struct が `PolicyEngine.swift` を編集せずに動くことの test
  - Routing 分離 — `Shared/Policy/` から `Shared/Routing/` への import 文が 0 であることの static check (grep ベース)

- **既存 JSON file 互換**:
  - 既存 `policy-constraints.json` の代表的な fixture を test resource に置き、新構造で問題なく decode できることを確認

---

## 7. Implementation Plan

実装は 4 phase に分割する。各 phase の終わりで commit、phase 4 完了で PR を Ready for Review に昇格させる。

### 7.1 Phase 1: Protocol 抽出と既存 condition の adapter 化

- `ConditionEvaluator` protocol を新設
- 既存 4 condition (`content`、`token_count`、`intent`、`privacy_level`) を concrete struct として実装
- 既存の `ConditionRule` 型を維持しつつ、`PolicyEngine` 内部で **新 protocol-based 経路を並列で走らせて** 結果が一致することを確認 (両走り検証)
- 既存 test 全 pass

### 7.2 Phase 2: PolicyEngine の orchestrator 化

- `PolicyEngine.swift` から switch 連鎖を削除
- `PolicyRule` に `evaluate()` method を追加、評価責任を移譲
- 旧 `evaluateCondition` 等の private helper を削除 (もしくは concrete Condition struct 内へ移動)
- 並列経路の片方を removeし、新経路だけにする
- 既存 test 全 pass

### 7.3 Phase 3: ConstraintStore の Codable 戦略更新

- `policy-constraints.json` の既存 fixture が migration なしで decode できることを test で confirm
- Codable encoding の output が既存 JSON と互換であることを確認 (round-trip test)

### 7.4 Phase 4: Extensibility の proof

- 1 個だけ「`PolicyEngine.swift` を編集せずに追加できる新 condition」のサンプルを実装する。例: `MessageLengthCondition` (token 換算前の生文字数) のような単純なもの
- これを使う rule を 1 個 fixture として追加し、test を書いて pass を確認する
- このサンプルで「core engine を編集していない」ことを diff で示す

---

## 8. Open Questions

実装フェーズで解く前提の open items:

1. **`any ConditionEvaluator` の Codable 戦略**: tagged enum (closed set) と type discriminator (open set) のどちらを取るか。前者は型安全、後者は extensibility が高い。`policy-constraints.json` の forward-compat と Swift の compile-time guarantee の trade-off。
2. **`Conditions/` / `Operators/` のサブディレクトリ命名**: 上述の通り、実装フェーズで confirm。
3. **`PolicyRulesProvider.notifyRulesUpdated()` の Future Hook**: 本 design では touch しないが、Phase 4 で「触らないこと」をコメントで明記する価値があるか。
4. **`type: ConstraintType` の役割**: 現状は `privacy` / `cost` / `performance` / `intent` の 4 値だが、本 design では condition を struct で識別するため、`type` field の意味が薄まる可能性がある。互換のため field 自体は残すが、将来 deprecation 候補として open にしておく。
5. **将来の hot-reload の hook 配置**: 本 design では実装しないが、**どこに hook を残すべきか** だけ note しておくべきか。`PolicyRulesProvider.notifyRulesUpdated()` で十分か、それとも `PolicyEngine` 側に observer 受け口を作るか。Open のまま残す。
6. **将来の trace 統合の hook 配置**: `PolicyEvaluationResult` に trace 用 metadata field を追加するか、それとも呼び出し側が自前で trace を生成するか。現状の `PolicyEvaluationResult.appliedConstraints` で十分かもしれない。Open のまま残す。

これらは本 design の approval を妨げない、実装中に Taka と sync しながら決める。

---

## 9. References

### Architecture Decision Records (rag-fish/RAGfish)

- ADR-0000 — Product Constitution (Human Sovereignty Principle)
- ADR-0004 — Architecture Constitution
- ADR-0005 — Client-side Routing as First-Class Principle
- ADR-0006 — Contract Lock v1.0.0
- ADR-0007 — External Client Integration via Integration Boundary

### Contracts (rag-fish/RAGfish)

- `docs/contracts/invocation-boundary.md`
- `docs/contracts/api-schema.md`
- `docs/contracts/constraint-contract.md`
- `docs/contracts/authority-model.md`

### Architecture Diagrams (rag-fish/RAGfish)

- `docs/architecture/architecture-standalone.puml`
- `docs/architecture/routing-decision.puml`
- `docs/architecture/execution-sequence.puml`

### Issues (rag-fish/NoesisNoema)

- #57 — EPIC4: Routing & Hybrid Execution
- #68 — PolicyEngine extensibility (本 design 対象)
- #69 — Human override mechanism (後続)
- #70 — Routing debug mode (後続)

### Existing Source

- `Shared/Policy/PolicyEngine.swift`
- `Shared/Policy/PolicyRule.swift`
- `Shared/Policy/PolicyRulesProvider.swift`
- `Shared/Policy/EditablePolicyRule.swift`
- `Shared/Policy/ConstraintStore.swift`
- `Shared/Policy/ConstraintEditorView.swift`
- `Shared/Policy/ConstraintEditorViewModel.swift`
- `Shared/Policy/ConstraintDetailView.swift`

### Existing Tests

- `Apps/macOS/NoesisNoema/Tests/PolicyEngineTests/PolicyEngineTests.swift`
- `Apps/macOS/NoesisNoema/Tests/PolicyEngineTests/ConstraintPersistenceTests.swift`
- `Apps/macOS/NoesisNoema/Tests/RouterTests/RouterDeterminismTests.swift`
- `Apps/macOS/NoesisNoema/Tests/ExecutionCoordinatorTests/ExecutionCoordinatorTests.swift`

### Related Predecessor Design Documents (rag-fish/NoesisNoema)

- `docs/EPIC1_Client_Authority_Hardening_Design.md`
- `docs/EPIC1_Constraint_Editor_Design.md`
- `docs/Router_Design_Compliance_Audit.md`

### Session 内ガイダンス

- Max からの #68 scope 補足 (2026-04-25 session 内、本 PR 内 Taka コメントとして引用済み)
- Constitutional self-check: rule は struct として持つ / evaluation は同期的・決定的 / routing とは完全分離

---

**End of design.**
