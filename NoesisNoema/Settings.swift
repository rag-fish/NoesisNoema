// Created by NoesisNoema on 2023-10-23.
// License: MIT License
// Project: NoesisNoema
// Description: Defines the Settings class for managing application settings.
// This class handles the configuration of various parameters such as model names, file paths, and user preferences.


import Foundation


class Settings {
    
    
    /**
        * Represents the settings for the NoesisNoema application.
        * - Properties:
        *   - selectedEmbeddingModelName: The name of the selected embedding model.
        *   - selectedLLMModelName: The name of the selected large language model (
        *     LLM).
        *   - selectedTokenizerName: The name of the selected tokenizer.
        *   - llmragFilePath: The file path for the LLM RAG
        *     (Retrieval-Augmented Generation) file.
        *   - tokenizerArchivePath: The file path for the tokenizer archive.
        *   - modelResourcePath: The file path for the model resources.
        *   - theme: The selected theme for the application.
     */
    /**
        * The language selected for the application.
        * This property allows users to set their preferred language for the application interface.
    */
    
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

    /**
        * Initializes the Settings with default values.
        * - Parameter embeddingModelName: The name of the embedding model.
        * - Parameter llmModelName: The name of the large language model (LLM).
        * - Parameter tokenizerName: The name of the tokenizer.
        * - Parameter llmragFilePath: The file path for the LLM RAG file.
        * - Parameter tokenizerArchivePath: The file path for the tokenizer archive.
        * - Parameter modelResourcePath: The file path for the model resources.
        * - Parameter theme: The selected theme for the application.
        */
    init(embeddingModelName: String = "defaultEmbeddingModel",
            llmModelName: String = "defaultLLMModel",
            tokenizerName: String = "defaultTokenizer",
            llmragFilePath: String = "default.llmrag",
            tokenizerArchivePath: String = "default.tokenizer",
            modelResourcePath: String = "default.model",
            theme: String = "defaultTheme",
    language: String = "en") {
        self.selectedEmbeddingModelName = embeddingModelName
        self.selectedLLMModelName = llmModelName
        self.selectedTokenizerName = tokenizerName
        self.llmragFilePath = llmragFilePath
        self.tokenizerArchivePath = tokenizerArchivePath
        self.modelResourcePath = modelResourcePath
        self.theme = theme
        self.language = language
        self.isUsingEmbeddedModel = false
        self.isUsingEmbeddedTokenizer = false
        self.isUsingEmbeddedLLMRagFile = false
    }
    
    
    
    /**
        * Loads the settings from a persistent storage.
        * This method should read the settings from a file or database and update the properties accordingly.
        * - Note: This method should handle any errors that may occur during loading.
     */
    func load() -> Void {
        // TODO: implement
        // Example: Load settings from a JSON file or database
        // self.selectedEmbeddingModelName = loadedSettings.embeddingModelName
        // self.selectedLLMModelName = loadedSettings.llmModelName
        // self.selectedTokenizerName = loadedSettings.tokenizerName
        // self.llmragFilePath = loadedSettings.llmragFilePath
        // self.tokenizerArchivePath = loadedSettings.tokenizerArchivePath
        // self.modelResourcePath = loadedSettings.modelResourcePath
        // self.theme = loadedSettings.theme
        // self.language = loadedSettings.language
        // self.isUsingEmbeddedModel = loadedSettings.isUsingEmbeddedModel
        // self.isUsingEmbeddedTokenizer = loadedSettings.isUsingEmbeddedTokenizer
        // self.isUsingEmbeddedLLMRagFile = loadedSettings.isUsingEmbeddedLLMRag
        // self.isUsingEmbeddedLLMRagFile = loadedSettings.isUsingEmbeddedLLMRagFile
        // Note: Ensure to handle any errors that may occur during loading, such as file not
        // found or invalid format.
        // You might want to throw an error or return a boolean indicating success or failure.
        // For example:
        // do {
        //     let loadedSettings = try loadSettingsFromFile()
        //     self.selectedEmbeddingModelName = loadedSettings.embeddingModelName
        //     self.selectedLLMModelName = loadedSettings.llmModelName
        //     self.selectedTokenizerName = loadedSettings.tokenizerName
        //     self.llmragFilePath = loadedSettings.llmragFilePath
        //     self.tokenizerArchivePath = loadedSettings.tokenizerArchivePath
        //     self.modelResourcePath = loadedSettings.modelResourcePath
        //     self.theme = loadedSettings.theme
        //     self.language = loadedSettings.language
        //     self.isUsingEmbeddedModel = loadedSettings.isUsingEmbeddedModel
        //     self.isUsingEmbeddedTokenizer = loadedSettings.isUsingEmbeddedTokenizer
        //     self.isUsingEmbeddedLLMRagFile = loadedSettings.isUsingEmbeddedLLMR
        // } catch {
        //     print("Error loading settings: \(error)")
        //     // Handle the error appropriately, such as showing an alert to the user or logging
        //     // the error for debugging purposes.
        // }
        // This is a placeholder implementation. You should replace it with actual loading logic.
        print("Loading settings...")
        // Simulate loading settings by setting default values
        self.selectedEmbeddingModelName = "defaultEmbeddingModel"
        self.selectedLLMModelName = "defaultLLMModel"
        self.selectedTokenizerName = "defaultTokenizer"
        self.llmragFilePath = "default.llmrag"
        self.tokenizerArchivePath = "default.tokenizer"
        self.modelResourcePath = "default.model"
        self.theme = "defaultTheme"
        self.language = "en"
        self.isUsingEmbeddedModel = false
        self.isUsingEmbeddedTokenizer = false
        self.isUsingEmbeddedLLMRagFile = false
    }
    
    /**
        * Saves the current settings to a persistent storage.
        * This method should write the current settings to a file or database.
        * - Note: This method should handle any errors that may occur during saving.
        */
    
    func save() -> Void {
        // TODO: implement
    }
    
    /**
        * Resets the settings to their default values.
        * This method should set all properties to their initial values as defined in the initializer.
        */
    func reset() -> Void {
        self.selectedEmbeddingModelName = "defaultEmbeddingModel"
        self.selectedLLMModelName = "defaultLLMModel"
        self.selectedTokenizerName = "defaultTokenizer"
        self.llmragFilePath = "default.llmrag"
        self.tokenizerArchivePath = "default.tokenizer"
        self.modelResourcePath = "default.model"
        self.theme = "defaultTheme"
        self.language = "en"
        self.isUsingEmbeddedModel = false
        self.isUsingEmbeddedTokenizer = false
        self.isUsingEmbeddedLLMRagFile = false
    }
    
    /**
        * Checks if the settings are valid.
        * This method should validate the current settings and return true if they are valid, false otherwise.
        * - Returns: A boolean indicating whether the settings are valid.
        */
    func useEmbeddedResources() -> Void {
        // TODO: implement
        self.isUsingEmbeddedModel = true
        self.isUsingEmbeddedTokenizer = true
        self.isUsingEmbeddedLLMRagFile = true
    }
    
}
