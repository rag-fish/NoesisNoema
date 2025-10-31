# Multi-Model Architecture - NoesisNoema

## 概要

NoesisNoemaは、複数のGGUFモデルを動的にロード・切り替え・推論できるマルチモデルアーキテクチャを実装しています。

## アーキテクチャ概要

```
┌─────────────────────────────────────────────────────────┐
│                      LlamaState                          │
│              (UIレイヤー・後方互換性維持)                  │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│                   ModelManager                           │
│        (動的モデル管理・ロード・切り替え)                  │
│  - scanAvailableModels()                                 │
│  - loadModel(id:)                                        │
│  - getCurrentEngine()                                    │
│  - autotuneParams()                                      │
└────────────────────┬────────────────────────────────────┘
                     │
         ┌───────────┴───────────┐
         ▼                       ▼
┌──────────────────┐    ┌──────────────────┐
│ InferenceEngine  │    │  ModelRegistry   │
│   (プロトコル)    │    │  (スペック管理)   │
└────────┬─────────┘    └──────────────────┘
         │                       ▲
         ▼                       │
┌──────────────────┐    ┌──────────────────┐
│LlamaInferenceEng │    │   GGUFReader     │
│  (llama.cpp実装)  │    │ (メタデータ抽出)  │
└────────┬─────────┘    └──────────────────┘
         │
         ▼
┌──────────────────┐
│  LlamaContext    │
│ (既存ラッパー)    │
└──────────────────┘
```

## 主要コンポーネント

### 1. InferenceEngine プロトコル
**ファイル**: `Shared/Llama/InferenceEngine.swift`

汎用的な推論エンジンインターフェース。任意のLLMアーキテクチャに対応可能。

```swift
protocol InferenceEngine: Actor {
    var metadata: GGUFMetadata { get }
    var runtimeParams: RuntimeParams { get set }
    var isDone: Bool { get async }

    func prepare(prompt: String) async throws
    func generateNextToken() async throws -> String?
    func generate(prompt: String, maxTokens: Int32) async throws -> String
    func configureSampling(temp: Float, topK: Int32, topP: Float, seed: UInt64) async
}
```

### 2. LlamaInferenceEngine
**ファイル**: `Shared/Llama/LlamaInferenceEngine.swift`

llama.cpp ベースの実装。LlamaContext を actor として安全にラップ。

**対応アーキテクチャ**:
- LLaMA (1/2/3)
- Qwen (1/2)
- Phi (2/3)
- Gemma
- Mistral
- GPT系

### 3. ModelManager
**ファイル**: `Shared/ModelManager.swift`

Responsible for dynamic management of multiple models.

**Key Features**:
- Model scanning (Resources/Models directory)
- Dynamic loading/unloading
- Auto-tuning based on hardware profile
- Model switching

**使用例**:
```swift
let manager = ModelManager.shared
await manager.scanAvailableModels()
try await manager.loadModel(id: "jan-v1-4b")

if let engine = manager.getCurrentEngine() {
    let result = try await engine.generate(prompt: "Hello", maxTokens: 100)
}
```

### 4. ModelRegistry
**ファイル**: `ModelRegistry/Core/ModelRegistry.swift`

モデルスペックの登録・検索を管理。

**主要機能**:
- GGUF メタデータ自動読み取り
- プリセットモデルスペック
- タグ・アーキテクチャ別検索

### 5. GGUFReader
**ファイル**: `ModelRegistry/IO/GGUFReader.swift`

GGUF ファイルからメタデータを抽出。

**抽出情報**:
- アーキテクチャ（llama, qwen, phi...）
- パラメータ数（4B, 8B, 20B...）
- コンテキスト長（2048, 8192, 32768...）
- 量子化形式（Q4_K_M, Q8_0...）
- レイヤー数、埋め込み次元、FFN次元

### 6. GoogleDriveDownloader
**ファイル**: `Shared/Utils/GoogleDriveDownloader.swift`

大規模GGUFファイルのダウンロードと検証。

**機能**:
- 再開可能ダウンロード（`.partial` ファイル）
- SHA256 完全性検証
- 進捗レポート
- 1MB チャンクでのメモリ効率的書き込み

**使用例**:
```swift
let downloader = GoogleDriveDownloader()
let task = GoogleDriveDownloader.DownloadTask(
    fileId: "1abc...xyz",
    fileName: "llama-3-8b.gguf",
    expectedSizeBytes: 8_000_000_000,
    sha256: "deadbeef..."
)

let url = try await downloader.download(
    task: task,
    to: modelDirectory,
    progressHandler: { progress in
        print("Progress: \(progress.percentage * 100)%")
    }
)
```

## 使用方法

## How to Add New Models

1. Copy GGUF file to `Resources/Models/`
2. Add file reference in Xcode (if necessary)
3. アプリ起動時に自動スキャンされる

```swift
await ModelManager.shared.scanAvailableModels()
```

### B. Google Drive からモデルをダウンロード

```swift
let downloader = GoogleDriveDownloader()
let task = GoogleDriveDownloader.DownloadTask(
    fileId: "YOUR_GOOGLE_DRIVE_FILE_ID",
    fileName: "model.gguf"
)

let modelURL = try await downloader.download(
    task: task,
    to: URL(fileURLWithPath: "Resources/Models")
)

// 自動的にModelRegistryがスキャン
await ModelManager.shared.scanAvailableModels()
```

### C. モデルを切り替えて推論

```swift
let manager = ModelManager.shared

// 小規模モデルをロード
try await manager.loadModel(id: "jan-v1-4b")
let result1 = try await manager.getCurrentEngine()?.generate(
    prompt: "Translate to Japanese: Hello",
    maxTokens: 50
)

// 大規模モデルに切り替え
try await manager.loadModel(id: "gpt-oss-20b")
let result2 = try await manager.getCurrentEngine()?.generate(
    prompt: "Write a poem about AI",
    maxTokens: 200
)
```

### D. LlamaState からの移行（段階的）

既存コードとの互換性を保ちながら、新APIを使用できます。

```swift
let state = LlamaState()

// 旧API（既存のまま動作）
let oldResult = await state.complete(text: "Hello")

// 新API（ModelManager経由）
try await state.loadModelViaManager(id: "jan-v1-4b")
let newResult = await state.completeViaManager(text: "Hello", maxTokens: 100)
```

## 自動チューニング

`ModelManager` はハードウェアプロファイルに基づいて自動的にパラメータを調整します。

### iOS デバイス
- 8GB+ RAM: nCtx=4096, nBatch=512, GPU=999層
- 6GB RAM: nCtx=2048, nBatch=256, GPU=64層
- 6GB未満: nCtx=1024, nBatch=128, GPU=32層

### macOS
- 16GB+ RAM: nCtx=8192, nBatch=1024, GPU=999層
- 8GB RAM: nCtx=4096, nBatch=512, GPU=80層
- 8GB未満: nCtx=2048, nBatch=256, GPU=40層

### 大規模モデル特別処理
- 20B+パラメータ: CPU強制、nCtx≤2048に制限
- 8B-20B: 部分的GPU利用、保守的な設定

## テスト

`Tests/ModelCompatibilityTests.swift` に包括的なテストスイートを用意。

```bash
# Xcode でテスト実行
⌘+U

# または特定のテストのみ
xcodebuild test -scheme NoesisNoema -only-testing:ModelCompatibilityTests/testGGUFMetadataExtraction
```

## エラーハンドリング

```swift
do {
    try await modelManager.loadModel(id: "unknown-model")
} catch InferenceError.modelNotLoaded {
    print("Model file not found")
} catch InferenceError.unsupportedArchitecture(let arch) {
    print("Architecture \(arch) not supported")
} catch InferenceError.outOfMemory {
    print("Not enough memory to load model")
} catch {
    print("Unknown error: \(error)")
}
```

## パフォーマンス最適化

### メモリ管理
- 不要なモデルは `unloadModel(id:)` で明示的にアンロード
- 大規模モデルはCPU専用で動作させる（iOS/低RAM環境）

### ストリーミング推論
```swift
await engine.prepare(prompt: "Tell me a story")

while await !engine.isDone {
    if let token = try await engine.generateNextToken() {
        print(token, terminator: "")
    }
}
```

### バッチ推論（高速）
```swift
let fullResponse = try await engine.generate(
    prompt: "Summarize this document...",
    maxTokens: 500
)
```

## トラブルシューティング

### モデルがスキャンされない
- `Resources/Models/` にファイルが存在するか確認
- Xcodeでファイル参照がターゲットに追加されているか確認
- `await ModelManager.shared.scanAvailableModels()` を明示的に呼び出す

### メモリ不足エラー
- より小さいモデルを使用（4B < 8B < 20B）
- RuntimeParams の nCtx/nBatch を減らす
- GPU層数を減らす（nGpuLayers = 0 でCPU専用）

### 推論が遅い
- GPU層数を増やす（macOS）
- より軽量な量子化を選択（Q4_K_M < Q8_0 < F16）
- バッチサイズを調整

### iOS でクラッシュ
- `LLAMA_NO_METAL=1` が設定されているか確認（LibLlama.swift）
- nGpuLayers = 0 を強制（iOS専用設定）
- より小さいコンテキスト長を使用

## ライセンス

MIT License

## 貢献

To add support for a new architecture:

1. `InferenceEngine` プロトコルに準拠した実装を作成
2. `ModelManager.loadModel()` の switch文に追加
3. `GGUFReader` でメタデータ推定ロジックを拡張
4. テストケースを追加

---

**作成日**: 2025年1月
**対象バージョン**: NoesisNoema v1.0+
