// Project: NoesisNoema
// File: LLMModel.swift
// Created by Раскольников on 2025/07/20.
// Description: Defines the LLMModel class for handling large language models.
// License: MIT License

import Foundation

class LLMModel {
    
    /**
        * Represents a large language model (LLM) with its properties and methods.
        *
        * - Properties:
        *   - name: The name of the model.
        *   - modelFile: The file containing the model.
        *   - version: The version of the model.
        *   - isEmbedded: A boolean indicating if the model is embedded.
        */
    var name: String
    
    /**
        * The file containing the model.
        * This file is used to load the model's configuration and weights.
        */
    var modelFile: String
    
    /**
        * The version of the model.
        * This is used to ensure compatibility with other components.
        */
    var version: String
    
    /**
        * Indicates whether the model is embedded.
        * This is used to determine if the model can be used directly or needs to be loaded from a file.
        */
    var isEmbedded: Bool

    /**
        * Initializes an LLMModel with the specified properties.
        * - Parameter name: The name of the model.
        * - Parameter modelFile: The file containing the model.
        * - Parameter version: The version of the model.
        * - Parameter isEmbedded: A boolean indicating if the model is embedded.
     
     */
    init(name: String, modelFile: String, version: String, isEmbedded: Bool = false) {
        self.name = name
        self.modelFile = modelFile
        self.version = version
        self.isEmbedded = isEmbedded
    }
    
    /**
        * Generates a response based on the provided prompt.
        * - Parameter prompt: The input text to generate a response for.
        * - Returns: A string containing the generated response.
        */
    func generate(prompt: String) -> String {
        // LibLlama/LlamaStateを使ったモデルファイル探索・推論
        let fileName = self.modelFile.isEmpty ? "llama3-8b.gguf" : self.modelFile
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        var checkedPaths: [String] = []
        let pathCWD = "\(cwd)/\(fileName)"
        checkedPaths.append(pathCWD)
        let exePath = CommandLine.arguments[0]
        let exeDir = URL(fileURLWithPath: exePath).deletingLastPathComponent().path
        let pathExeDir = "\(exeDir)/\(fileName)"
        if pathExeDir != pathCWD { checkedPaths.append(pathExeDir) }
        if let bundleResourceURL = Bundle.main.resourceURL {
            let pathBundle = bundleResourceURL.appendingPathComponent(fileName).path
            if pathBundle != pathCWD && pathBundle != pathExeDir { checkedPaths.append(pathBundle) }
        }
        for path in checkedPaths {
            if fm.fileExists(atPath: path) {
                let semaphore = DispatchSemaphore(value: 0)
                var result = ""
                Task {
                    let llamaState = await LlamaState()
                    do {
                        try await llamaState.loadModel(modelUrl: URL(fileURLWithPath: path))
                        let response: String = await llamaState.complete(text: prompt)
                        result = response
                    } catch {
                        result = "[LLMModel] 推論エラー: \(error)"
                    }
                    semaphore.signal()
                }
                semaphore.wait()
                return result
            }
        }
        return "[LLMModel] モデルファイルが見つかりません: \(fileName)"
    }

    /**
        * Loads the model from the specified file.
        * - Parameter file: The file to load the model from.
        */
    func loadModel(file: Any) -> Void {
        // 実際はモデルファイルをロードするが、ここではダミー実装
        print("Loading LLM model from file: \(file)")
        self.isEmbedded = true
        self.modelFile = String(describing: file)
        print("Model loaded: \(name), version: \(version), file: \(modelFile)")
    }
}
