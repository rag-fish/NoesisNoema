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

### 1. InferenceEngine Protocol
**File**: `Shared/Llama/InferenceEngine.swift`

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
**File**: `Shared/Llama/LlamaInferenceEngine.swift`

llama.cpp ベースの実装。LlamaContext を actor として安全にラップ。

**対応アーキテクチャ**:
- LLaMA (1/2/3)
- Qwen (1/2)
- Phi (2/3)
- Gemma
- Mistral
- GPT系

### 3. ModelManager
**File**: `Shared/ModelManager.swift`

複数モデルの動的管理を担当。

**主要機能**:
- モデルスキャン（Resources/Models ディレクトリ）
- 動的ロード/アンロード
- ハードウェアプロファイルに基づく自動チューニング
- モデル切り替え

**Usage Example**:
```swift
let manager = ModelManager.shared
await manager.scanAvailableModels()
try await manager.loadModel(id: "jan-v1-4b")

if let engine = manager.getCurrentEngine() {
    let result = try await engine.generate(prompt: "Hello", maxTokens: 100)
}
```

### 4. ModelRegistry
**File**: `ModelRegistry/Core/ModelRegistry.swift`

Manages model spec registration and search.

**Key Features**:
- Automatic GGUF metadata reading
- Preset model specs
- Search by tags and architecture

### 5. GGUFReader
**File**: `ModelRegistry/IO/GGUFReader.swift`

Extracts metadata from GGUF files.

**Extracted Information**:
- Architecture (llama, qwen, phi...)
- Parameter count (4B, 8B, 20B...)
- Context length (2048, 8192, 32768...)
- Quantization format (Q4_K_M, Q8_0...)
- Layer count, embedding dimension, FFN dimension

### 6. GoogleDriveDownloader
**File**: `Shared/Utils/GoogleDriveDownloader.swift`

Downloads and validates large GGUF files.

**Features**:
- Resumable downloads (`.partial` files)
- SHA256 integrity verification
- Progress reporting
- Memory-efficient writing in 1MB chunks

**Usage Example**:
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

### A. 新しいモデルを追加する（手動配置）

1. GGUF ファイルを `Resources/Models/` にコピー
2. Xcodeでファイル参照を追加（必要に応じて）
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

新しいアーキテクチャのサポートを追加する場合:

1. `InferenceEngine` プロトコルに準拠した実装を作成
2. `ModelManager.loadModel()` の switch文に追加
3. `GGUFReader` でメタデータ推定ロジックを拡張
4. テストケースを追加

---

**作成日**: 2025年1月
**対象バージョン**: NoesisNoema v1.0+
