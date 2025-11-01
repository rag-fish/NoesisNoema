// filepath: NoesisNoema/Shared/Llama/InferenceEngine.swift
// Project: NoesisNoema
// Description: Generic inference engine protocol for multi-model support
// License: MIT License

import Foundation

/// 汎用推論エンジンインターフェース - 任意のGGUFモデルに対応
protocol InferenceEngine: Actor {
    /// モデルメタデータ
    var metadata: GGUFMetadata { get }

    /// ランタイムパラメータ
    var runtimeParams: RuntimeParams { get set }

    /// モデル情報（デバッグ用）
    func modelInfo() async -> String

    /// システム情報
    func systemInfo() async -> String

    /// 推論準備（プロンプト初期化）
    func prepare(prompt: String) async throws

    /// ストリーミング推論（1トークンずつ生成）
    func generateNextToken() async throws -> String?

    /// バッチ推論（全トークン生成）
    func generate(prompt: String, maxTokens: Int32) async throws -> String

    /// 推論完了判定
    var isDone: Bool { get async }

    /// サンプリング設定
    func configureSampling(temp: Float, topK: Int32, topP: Float, seed: UInt64) async

    /// 冗長ログ制御
    func setVerbose(_ on: Bool) async
}

/// InferenceEngine のエラー型
enum InferenceError: Error, LocalizedError {
    case modelNotLoaded
    case incompatibleModel(String)
    case outOfMemory
    case generationFailed(String)
    case unsupportedArchitecture(String)
    case contextInitializationFailed

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Model has not been loaded"
        case .incompatibleModel(let reason):
            return "Incompatible model: \(reason)"
        case .outOfMemory:
            return "Out of memory during inference"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        case .unsupportedArchitecture(let arch):
            return "Unsupported architecture: \(arch)"
        case .contextInitializationFailed:
            return "Failed to initialize inference context"
        }
    }
}
