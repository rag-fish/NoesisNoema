// Created by NoesisNoema on 2023/10/30.
// License: MIT License
// Project: NoesisNoema
// Description: Defines the RAGApp class for managing the RAG application.

import Foundation


class RAGApp {


    /**
        * Represents the RAG application with its core components.
        * - Properties:
        *   - documentManager: The document manager used for handling documents.
        *   - modelManager: The model manager used for managing models.
        *   - settings: The settings for the RAG application.
        * - Initializer: Initializes the RAGApp with the specified document manager, model manager, and settings.
        * - Note: This class serves as the main entry point for the RAG application,
        *         encapsulating the document management, model management, and application settings.
        * - Usage: Create an instance of RAGApp to manage the core components of the
        *         RAG application, allowing for document imports, model management, and configuration settings.
        * - Example:
        *   ```swift
        *   let documentManager = DocumentManager()
        *   let modelManager = ModelManager()
        *   let settings = Settings()
        *   let ragApp = RAGApp(documentManager: documentManager, modelManager:
        modelManager, settings: settings)
        *   ```
        * - SeeAlso: `DocumentManager`, `ModelManager`, `Settings`
     */
    var documentManager: DocumentManager

    /// The model manager used for managing models.
    var modelManager: ModelManager

    /// The settings for the RAG application.
    var settings: Settings

    /**
        * Initializes the RAGApp with the specified document manager, model manager, and settings.
        * - Parameters:
        *   - documentManager: The document manager used for handling documents.
        *   - modelManager: The model manager used for managing models.
        *   - settings: The settings for the RAG application.
        * - Returns: An instance of RAGApp.
        * - Note: This initializer sets up the core components of the RAG application.
        */
    init(documentManager: DocumentManager, modelManager: ModelManager, settings: Settings) {
        self.documentManager = documentManager
        self.modelManager = modelManager
        self.settings = settings

        // Additional setup can be done here if needed
    }


}
