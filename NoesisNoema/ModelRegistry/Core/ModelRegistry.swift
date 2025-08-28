// Project: NoesisNoema
// File: ModelRegistry.swift
// Created by Copilot on 2025/08/23
// Description: Model registry for managing model specifications and auto-tuning
// License: MIT License

import Foundation

/// Registry for managing model specifications and auto-tuning parameters
actor ModelRegistry {

    /// Singleton instance
    static let shared = ModelRegistry()

    /// Registered model specifications
    private var modelSpecs: [String: ModelSpec] = [:]

    /// File paths being scanned
    private var scanningPaths: Set<String> = []

    /// Predefined model specifications (fallbacks)
    private let predefinedSpecs: [ModelSpec] = [
        ModelSpec(
            id: "jan-v1-4b",
            name: "Jan-V1-4B",
            modelFile: "Jan-v1-4B-Q4_K_M.gguf",
            version: "4B",
            metadata: GGUFMetadata(
                architecture: "qwen",
                parameterCount: 4.0,
                contextLength: 32768,
                quantization: "Q4_K_M",
                layerCount: 32,
                embeddingDimension: 2048,
                feedForwardDimension: 5504,
                attentionHeads: 32,
                supportsFlashAttention: true
            ),
            tags: ["qwen", "small", "q4_k_m", "long-context"],
            description: "Jan V1 4B parameter model with Qwen architecture, Q4_K_M quantization"
        ),
        ModelSpec(
            id: "llama-3-8b",
            name: "Llama-3",
            modelFile: "llama3-8b.gguf",
            version: "8B",
            metadata: GGUFMetadata(
                architecture: "llama",
                parameterCount: 8.0,
                contextLength: 8192,
                quantization: "Q4_K_M",
                layerCount: 32,
                embeddingDimension: 4096,
                feedForwardDimension: 14336,
                attentionHeads: 32,
                supportsFlashAttention: true
            ),
            tags: ["llama", "medium", "q4_k_m", "medium-context"],
            description: "LLaMA 3 8B parameter model with standard quantization"
        ),
        ModelSpec(
            id: "phi-3-mini",
            name: "Phi-3-mini",
            modelFile: "phi-3-mini.gguf",
            version: "mini",
            metadata: GGUFMetadata(
                architecture: "phi3",
                parameterCount: 3.8,
                contextLength: 4096,
                quantization: "Q4_K_M",
                layerCount: 32,
                embeddingDimension: 3072,
                feedForwardDimension: 8192,
                attentionHeads: 32,
                supportsFlashAttention: true
            ),
            tags: ["phi", "small", "q4_k_m", "medium-context"],
            description: "Phi-3 Mini 3.8B parameter model optimized for efficiency"
        ),
        ModelSpec(
            id: "gemma-2b",
            name: "Gemma-2B",
            modelFile: "gemma-2b.gguf",
            version: "2B",
            metadata: GGUFMetadata(
                architecture: "gemma",
                parameterCount: 2.0,
                contextLength: 2048,
                quantization: "Q4_K_M",
                layerCount: 18,
                embeddingDimension: 2048,
                feedForwardDimension: 5632,
                attentionHeads: 8,
                supportsFlashAttention: false
            ),
            tags: ["gemma", "small", "q4_k_m", "short-context"],
            description: "Gemma 2B parameter lightweight model"
        ),
        ModelSpec(
            id: "gpt-oss-20b",
            name: "GPT-OSS-20B",
            modelFile: "gpt-oss-20b-Q4_K_S.gguf",
            version: "20B",
            metadata: GGUFMetadata(
                architecture: "gpt",
                parameterCount: 20.0,
                contextLength: 4096,
                quantization: "Q4_K_S",
                layerCount: 44,
                embeddingDimension: 6144,
                feedForwardDimension: 24576,
                attentionHeads: 48,
                supportsFlashAttention: false
            ),
            tags: ["gpt", "large", "q4_k_s", "medium-context"],
            description: "GPT-OSS 20B parameter large language model"
        )
    ]

    private init() {
        // Initialize with predefined specs
        for spec in predefinedSpecs {
            modelSpecs[spec.id] = spec
        }
    }

    /// Register a model specification
    func register(_ spec: ModelSpec) {
        modelSpecs[spec.id] = spec
    }

    /// Update runtime params for a given model id (if exists)
    func updateRuntimeParams(for id: String, params: RuntimeParams) {
        guard var spec = modelSpecs[id] else { return }
        spec.runtimeParams = params
        modelSpecs[id] = spec
    }

    /// Get a model specification by ID
    func getModelSpec(id: String) -> ModelSpec? {
        return modelSpecs[id]
    }

    /// Get all registered model specifications
    func getAllModelSpecs() -> [ModelSpec] {
        return Array(modelSpecs.values).sorted { $0.name < $1.name }
    }

    /// Get available (file exists) model specifications
    func getAvailableModelSpecs() -> [ModelSpec] {
        return getAllModelSpecs().filter { $0.isAvailable }
    }

    /// Find model specifications by tag
    func findModelSpecs(withTag tag: String) -> [ModelSpec] {
        return getAllModelSpecs().filter { spec in
            spec.tags.contains { $0.lowercased() == tag.lowercased() }
        }
    }

    /// Find model specifications by architecture
    func findModelSpecs(withArchitecture architecture: String) -> [ModelSpec] {
        return getAllModelSpecs().filter { spec in
            spec.metadata.architecture.lowercased() == architecture.lowercased() }
    }

    /// Scan for GGUF files in standard locations and register them
    func scanForModels() async {
        let searchPaths = getModelSearchPaths()

        for path in searchPaths {
            if !scanningPaths.contains(path) {
                scanningPaths.insert(path)
                await scanDirectory(path)
                scanningPaths.remove(path)
            }
        }
    }

    /// Scan for GGUF files in a specific directory
    func scanDirectory(_ directoryPath: String) async {
        guard FileManager.default.fileExists(atPath: directoryPath) else {
            return
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: directoryPath)
            let ggufFiles = contents.filter { $0.lowercased().hasSuffix(".gguf") }

            for fileName in ggufFiles {
                let fullPath = "\(directoryPath)/\(fileName)"
                await registerGGUFFile(at: fullPath)
            }
        } catch {
            print("[ModelRegistry] Error scanning directory \(directoryPath): \(error)")
        }
    }

    /// Register a GGUF file by reading its metadata
    func registerGGUFFile(at filePath: String) async {
        guard GGUFReader.isValidGGUFFile(at: filePath) else {
            print("[ModelRegistry] Invalid GGUF file: \(filePath)")
            return
        }

        do {
            let metadata = try await GGUFReader.readMetadata(from: filePath)
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent
            let baseName = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent

            // Generate ID from filename
            let id = generateModelId(from: baseName)

            // Check if we already have this model registered
            if let existingSpec = modelSpecs[id] {
                // Update existing spec with actual file path and availability
                var updatedSpec = existingSpec
                updatedSpec.filePath = filePath
                updatedSpec.isAvailable = true
                updatedSpec.metadata = metadata
                // Re-tune parameters with actual metadata
                updatedSpec.runtimeParams = autoTuneParameters(metadata: metadata, baseParams: RuntimeParams.oomSafeDefaults())
                modelSpecs[id] = updatedSpec
            } else {
                // Create new spec
                let spec = ModelSpec.withAutoTunedParams(
                    id: id,
                    name: generateModelName(from: baseName),
                    modelFile: fileName,
                    version: extractVersion(from: baseName),
                    metadata: metadata,
                    filePath: filePath
                )
                modelSpecs[id] = spec
            }

            print("[ModelRegistry] Registered model: \(id) at \(filePath)")
        } catch {
            print("[ModelRegistry] Error reading GGUF metadata from \(filePath): \(error)")
        }
    }

    /// Update model availability by checking file paths
    func updateModelAvailability() async {
        for (id, spec) in modelSpecs {
            var updatedSpec = spec

            if let filePath = spec.filePath {
                updatedSpec.isAvailable = FileManager.default.fileExists(atPath: filePath)
            } else {
                // Try to find the model file in standard locations
                let searchPaths = getModelSearchPaths()
                updatedSpec.isAvailable = false

                for searchPath in searchPaths {
                    let candidatePath = "\(searchPath)/\(spec.modelFile)"
                    if FileManager.default.fileExists(atPath: candidatePath) {
                        updatedSpec.filePath = candidatePath
                        updatedSpec.isAvailable = true
                        break
                    }
                }
            }

            modelSpecs[id] = updatedSpec
        }
    }

    /// Get model information formatted for CLI display
    func getModelInfo(id: String) -> String? {
        guard let spec = modelSpecs[id] else {
            return nil
        }

        let availabilityStatus = spec.isAvailable ? "✓ Available" : "✗ Not Found"
        let fileLocation = spec.filePath ?? "Unknown"
        let sizeGB = String(format: "%.1f GB", Double(spec.metadata.modelSizeBytes) / (1024 * 1024 * 1024))
        let paramStr = String(format: "%.1fB", spec.metadata.parameterCount)

        return """
        Model ID: \(spec.id)
        Name: \(spec.name)
        Version: \(spec.version)
        Status: \(availabilityStatus)
        File: \(spec.modelFile)
        Location: \(fileLocation)

        Architecture: \(spec.metadata.architecture)
        Parameters: \(paramStr)
        Quantization: \(spec.metadata.quantization)
        File Size: \(sizeGB)
        Context Length: \(spec.metadata.contextLength)
        Vocab Size: \(spec.metadata.vocabSize)
        Layers: \(spec.metadata.layerCount)
        Embedding Dim: \(spec.metadata.embeddingDimension)
        FF Dim: \(spec.metadata.feedForwardDimension)
        Attention Heads: \(spec.metadata.attentionHeads)
        Flash Attention: \(spec.metadata.supportsFlashAttention ? "Yes" : "No")

        Runtime Parameters:
        - Threads: \(spec.runtimeParams.nThreads)
        - GPU Layers: \(spec.runtimeParams.nGpuLayers)
        - Context Size: \(spec.runtimeParams.nCtx)
        - Batch Size: \(spec.runtimeParams.nBatch)
        - Memory Limit: \(spec.runtimeParams.memoryLimitMB) MB
        - Temperature: \(spec.runtimeParams.temperature)
        - Top-K: \(spec.runtimeParams.topK)
        - Top-P: \(spec.runtimeParams.topP)

        Tags: \(spec.tags.joined(separator: ", "))
        Description: \(spec.description)
        """
    }

    /// Auto-tune runtime parameters based on metadata and system capabilities
    private func autoTuneParameters(metadata: GGUFMetadata, baseParams: RuntimeParams) -> RuntimeParams {
        return ModelSpec.autoTuneParameters(metadata: metadata, baseParams: baseParams)
    }

    /// Get standard model search paths
    private func getModelSearchPaths() -> [String] {
        let fileManager = FileManager.default
        var paths: [String] = []

        // Current working directory
        paths.append(fileManager.currentDirectoryPath)

        // Executable directory
        let exePath = CommandLine.arguments[0]
        let exeDir = URL(fileURLWithPath: exePath).deletingLastPathComponent().path
        if !paths.contains(exeDir) {
            paths.append(exeDir)
        }

        // App bundle resources
        if let resourcePath = Bundle.main.resourcePath {
            paths.append(resourcePath)
            paths.append("\(resourcePath)/Models")
            paths.append("\(resourcePath)/Resources/Models")
        }

        // User directories (platform-aware)
        let homeDirPath: String? = {
            #if os(iOS)
            return NSHomeDirectory()
            #else
            return fileManager.homeDirectoryForCurrentUser.path
            #endif
        }()
        if let homeDir = homeDirPath {
            paths.append("\(homeDir)/Downloads")
            paths.append("\(homeDir)/Documents/Models")
            paths.append("\(homeDir)/.noesisnoema/models")
        }

        // System-wide model directories (desktop-oriented; filtered by existence below)
        paths.append("/usr/local/share/noesisnoema/models")
        paths.append("/opt/noesisnoema/models")

        return paths.filter { fileManager.fileExists(atPath: $0) }
    }

    /// Generate a model ID from filename
    private func generateModelId(from baseName: String) -> String {
        return baseName.lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ".", with: "_")
    }

    /// Generate a human-readable model name from filename
    private func generateModelName(from baseName: String) -> String {
        // Convert common patterns to readable names
        let name = baseName
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "-q4-k-m", with: "")
            .replacingOccurrences(of: "-q4-k-s", with: "")
            .replacingOccurrences(of: "-q8-0", with: "")
            .replacingOccurrences(of: "-gguf", with: "")

        return name.split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    /// Extract version from filename
    private func extractVersion(from baseName: String) -> String {
        let patterns = [
            "\\d+b",     // 7b, 13b, etc.
            "\\d+\\.\\d+b", // 3.8b, etc.
            "mini",
            "small",
            "medium",
            "large",
            "xl"
        ]

        let lowercased = baseName.lowercased()
        for pattern in patterns {
            if let range = lowercased.range(of: pattern, options: .regularExpression) {
                return String(lowercased[range]).uppercased()
            }
        }

        return "unknown"
    }
}
