class Settings {
    var selectedEmbeddingModelName: String
    var selectedLLMModelName: String
    var selectedTokenizerName: String
    var llmragFilePath: String
    var tokenizerArchivePath: String
    var modelResourcePath: String
    var theme: String
    var language: String
    var isUsingEmbeddedModel: Bool
    var isUsingEmbeddedTokenizer: Bool
    var isUsingEmbeddedLLMRagFile: Bool

    func load() -> Void {
        // TODO: implement
    }
    func save() -> Void {
        // TODO: implement
    }
    func useEmbeddedResources() -> Void {
        // TODO: implement
    }
}
