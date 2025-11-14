// Project: NoesisNoema
// File: LLMModel.swift
// Created by Раскольников on 2025/07/20.
// Description: Defines the LLMModel class for handling large language models.
// License: MIT License
// REFACTORED: 2025-11-14 - Unified with CLI pipeline, removed DispatchSemaphore

import Foundation

class LLMModel: @unchecked Sendable {

    var name: String
    var modelFile: String
    var version: String
    var isEmbedded: Bool

    init(name: String, modelFile: String, version: String, isEmbedded: Bool = false) {
        self.name = name
        self.modelFile = modelFile
        self.version = version
        self.isEmbedded = isEmbedded
    }

    // MARK: - Public API

    /// Synchronous wrapper for compatibility
    func generate(prompt: String) -> String {
        return generate(prompt: prompt, context: nil)
    }

    /// Synchronous wrapper - DEPRECATED: Use generateAsync() for new code
    func generate(prompt: String, context: String?) -> String {
        var result = ""
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                result = try await generateAsync(prompt: prompt, context: context)
            } catch {
                result = "[LLMModel] Error: \(error.localizedDescription)"
            }
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    /// ✅ ASYNC GENERATION - Uses unified NoesisCompletion pipeline
    func generateAsync(prompt: String, context: String?) async throws -> String {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🎬 [LLMModel] generateAsync ENTRY POINT")
        print("   Model: \(name)")
        print("   Model file: \(modelFile)")
        print("   Question: \(prompt.count) chars - '\(prompt.prefix(80))...'")
        print("   Context: \(context != nil ? "\(context!.count) chars" : "none")")
        SystemLog().logEvent(event: "[LLMModel] generateAsync: model=\(name), q=\(prompt.count)chars")

        // Step 1: Resolve model path
        print("🔍 [LLMModel] STEP 1: Resolving model path...")
        let fileName = modelFile.isEmpty ? "Jan-v1-4B-Q4_K_M.gguf" : modelFile
        print("   File name: \(fileName)")
        let modelPath = try resolveModelPath(fileName: fileName)
        print("✅ [LLMModel] Model path resolved: \(modelPath)")

        // Step 2: Get runtime params
        print("🔍 [LLMModel] STEP 2: Building runtime params...")
        let params = await buildRuntimeParams()
        print("✅ [LLMModel] Params: temp=\(params.temp) topK=\(params.topK) topP=\(params.topP) nLen=\(params.nLen)")

        // Step 3: Call unified pipeline (NO DispatchSemaphore!)
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🚀 [LLMModel] STEP 3: Calling runNoesisCompletion() NOW...")
        print("   modelPath: \(modelPath)")
        print("   question: \(prompt.prefix(80))...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let answer = try await runNoesisCompletion(
            question: prompt,
            context: context,
            modelPath: modelPath,
            params: params
        )

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("✅ [LLMModel] runNoesisCompletion RETURNED!")
        print("   Answer length: \(answer.count) chars")
        print("   Preview: \(answer.prefix(100))...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        SystemLog().logEvent(event: "[LLMModel] generateAsync complete: \(answer.count) chars")

        return answer
    }

    // MARK: - Helpers

    private func resolveModelPath(fileName: String) throws -> String {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        var checkedPaths: [String] = []

        // 1) CWD
        checkedPaths.append("\(cwd)/\(fileName)")

        // 2) Executable directory
        let exePath = CommandLine.arguments[0]
        let exeDir = URL(fileURLWithPath: exePath).deletingLastPathComponent().path
        checkedPaths.append("\(exeDir)/\(fileName)")

        // 3) App Bundle
        if let bundleResourceURL = Bundle.main.resourceURL {
            checkedPaths.append(bundleResourceURL.appendingPathComponent(fileName).path)
            for sub in ["Models", "Resources/Models", "Resources", "NoesisNoema/Resources/Models"] {
                checkedPaths.append(bundleResourceURL.appendingPathComponent(sub).appendingPathComponent(fileName).path)
            }
        }

        // 4) Resource lookups
        let nameNoExt = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        if let url = Bundle.main.url(forResource: nameNoExt, withExtension: ext, subdirectory: nil) {
            checkedPaths.append(url.path)
        }
        if let url = Bundle.main.url(forResource: nameNoExt, withExtension: ext, subdirectory: "Models") {
            checkedPaths.append(url.path)
        }
        if let url = Bundle.main.url(forResource: nameNoExt, withExtension: ext, subdirectory: "Resources/Models") {
            checkedPaths.append(url.path)
        }

        // Find first existing path
        for path in Array(Set(checkedPaths)) { // Deduplicate
            if fm.fileExists(atPath: path) {
                #if DEBUG
                print("✅ [LLMModel] Found model at: \(path)")
                #endif
                return path
            }
        }

        // Not found
        let errorMsg = "Model file not found: \(fileName). Checked \(checkedPaths.count) locations."
        #if DEBUG
        print("❌ [LLMModel] \(errorMsg)")
        for (i, p) in Array(Set(checkedPaths)).enumerated() {
            print("   \(i+1). \(p)")
        }
        #endif
        throw NSError(domain: "LLMModel", code: 404, userInfo: [NSLocalizedDescriptionKey: errorMsg])
    }

    private func buildRuntimeParams() async -> LlamaRuntimeParams {
        // Get preset from ModelManager
        let presetName = await ModelManager.shared.currentLLMPreset

        switch presetName {
        case "factual":
            return LlamaRuntimeParams(temp: 0.2, topK: 40, topP: 0.85, nLen: 384)
        case "balanced":
            return LlamaRuntimeParams(temp: 0.5, topK: 60, topP: 0.9, nLen: 512)
        case "creative":
            return LlamaRuntimeParams(temp: 0.9, topK: 100, topP: 0.95, nLen: 768)
        case "json":
            return LlamaRuntimeParams(temp: 0.2, topK: 40, topP: 0.9, nLen: 512)
        case "code":
            return LlamaRuntimeParams(temp: 0.3, topK: 50, topP: 0.9, nLen: 640)
        default: // "auto" or unknown
            return .balanced
        }
    }

    /// Legacy method for loading model (kept for compatibility)
    func loadModel(file: Any) -> Void {
        print("Loading LLM model from file: \(file)")
        self.isEmbedded = true
        self.modelFile = String(describing: file)
        print("Model loaded: \(name), version: \(version), file: \(modelFile)")
    }
}
