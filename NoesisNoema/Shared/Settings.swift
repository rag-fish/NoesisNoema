// Created by NoesisNoema on 2023-10-23.
// License: MIT License
// Project: NoesisNoema
// Description: Defines the Settings class for managing application settings.
// This class handles the configuration of various parameters such as model names, RAGpack file paths, and user preferences.


import Foundation


class Settings {
    // RAGpack (.zip) のパス
    var ragpackFilePath: String
    // モデルリソースのパス
    var modelResourcePath: String
    // 選択中の埋め込みモデル名
    var selectedEmbeddingModelName: String
    // 選択中のLLMモデル名
    var selectedLLMModelName: String
    // UIテーマ
    var theme: String
    // UI言語
    var language: String
    // RAGpackが埋め込み型か
    var isUsingEmbeddedRAGpack: Bool
    // モデルが埋め込み型か
    var isUsingEmbeddedModel: Bool

    // RAGpack(.zip)の読み込み
    func loadRAGpack() -> Bool {
        // TODO: RAGpack(.zip)のパスragpackFilePathから読み込み、必要なデータをロード
        // 例: DocumentManager.shared.importDocument(file: ragpackFilePath)
        print("Loading RAGpack from: \(ragpackFilePath)")
        // 実装例: 成功ならtrue, 失敗ならfalse
        return true
    }

    // モデルリソースの読み込み
    func loadModelResource() -> Bool {
        // TODO: modelResourcePathからモデルをロード
        print("Loading model resource from: \(modelResourcePath)")
        return true
    }

    // 設定のロード
    func load() {
        // TODO: 設定ファイルやUserDefaultsから設定値をロード
        print("Settings loaded.")
    }

    // 設定の保存
    func save() {
        // TODO: 設定値をファイルやUserDefaultsに保存
        print("Settings saved.")
    }

    // 設定のリセット
    func reset() {
        self.selectedEmbeddingModelName = "defaultEmbeddingModel"
        self.selectedLLMModelName = "defaultLLMModel"
        self.ragpackFilePath = "default.ragpack.zip"
        self.modelResourcePath = "default.model"
        self.theme = "defaultTheme"
        self.language = "en"
        self.isUsingEmbeddedModel = false
        self.isUsingEmbeddedRAGpack = false
    }

    // 埋め込みリソース利用フラグ
    func useEmbeddedResources() {
        self.isUsingEmbeddedModel = true
        self.isUsingEmbeddedRAGpack = true
    }

    // 初期化
    init(
        embeddingModelName: String = "defaultEmbeddingModel",
        llmModelName: String = "defaultLLMModel",
        ragpackFilePath: String = "default.ragpack.zip",
        modelResourcePath: String = "default.model",
        theme: String = "defaultTheme",
        language: String = "en"
    ) {
        self.selectedEmbeddingModelName = embeddingModelName
        self.selectedLLMModelName = llmModelName
        self.ragpackFilePath = ragpackFilePath
        self.modelResourcePath = modelResourcePath
        self.theme = theme
        self.language = language
        self.isUsingEmbeddedModel = false
        self.isUsingEmbeddedRAGpack = false
    }
}
