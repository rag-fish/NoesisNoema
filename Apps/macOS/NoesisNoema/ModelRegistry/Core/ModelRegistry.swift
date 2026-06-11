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
    ///
    /// Only Llama 3.2 3B is declared — the single GGUF that actually ships on device.
    /// Earlier ghost/retired LLM entries were removed in the registry cleanup ahead
    /// of ADR-0011 (replaceable GGUF embedder).
    private let predefinedSpecs: [ModelSpec] = [
        ModelSpec(
            id: "llama-3.2-3b",
            name: "Llama 3.2 3B",
            modelFile: "llama-3.2-3b-instruct-q4_k_m.gguf",
            version: "3B",
            metadata: GGUFMetadata(
                architecture: "llama",
                parameterCount: 3.2,
                contextLength: 131072,
                quantization: "Q4_K_M",
                layerCount: 28,
                embeddingDimension: 3072,
                feedForwardDimension: 8192,
                attentionHeads: 24,
                supportsFlashAttention: true
            ),
            tags: ["llama", "small", "q4_k_m", "long-context", "instruct"],
            description: "Llama 3.2 3B Instruct, Q4_K_M quantization — default on-device model"
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

    /// Decide whether a GGUF file is an embedding-only model that must never be
    /// offered as a chat LLM. Embedders (nomic-bert, BGE, E5, Jina, …) have no
    /// generation head; asked to generate they emit reserved-vocab `[unusedN]`
    /// tokens. Pure + deterministic so it is trivially unit-testable.
    ///
    /// Detection (any single signal is sufficient):
    ///   1. File-name marker — base name contains `embed`, `-bert`, or `jina-`.
    ///   2. GGUF `architecture` metadata contains `bert` (nomic-bert, jina-bert,
    ///      mpnet-bert, plain bert, …).
    ///
    /// NOTE: `GGUFMetadata` does not currently surface a pooling-type field; a
    /// non-nil pooling marker would be an orthogonal third signal, but adding it
    /// to `GGUFReader` is out of scope here — the two signals above cover every
    /// embedder Nomic / Jina / BGE / E5 ships today.
    static func looksLikeEmbedder(fileName: String, metadata: GGUFMetadata) -> Bool {
        let lower = fileName.lowercased()
        if lower.contains("embed") || lower.contains("-bert") || lower.contains("jina-") {
            return true
        }
        if metadata.architecture.lowercased().contains("bert") {
            return true
        }
        return false
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

        #if DEBUG
        assertNoEmbeddersRegistered()
        #endif
    }

    #if DEBUG
    /// Startup smoke (matches the PR #99 / #100 manual-smoke pattern): after a full
    /// scan, no registered spec's `modelFile` may look like an embedder. If one
    /// slips through (a future embedder that dodges the file-name / architecture
    /// heuristics), this logs loudly in DEBUG so it is caught before UAT — the LLM
    /// picker driving an embedder is exactly the [unusedN]-garbage bug this guards.
    private func assertNoEmbeddersRegistered() {
        let offenders = getAvailableModelSpecs().filter {
            $0.modelFile.lowercased().contains("embed")
                || $0.modelFile.lowercased().contains("-bert")
                || $0.metadata.architecture.lowercased().contains("bert")
        }
        if offenders.isEmpty {
            print("[ModelRegistry] embedder-exclusion smoke PASSED — "
                  + "\(getAvailableModelSpecs().count) available model(s), none look like embedders.")
        } else {
            let names = offenders.map { $0.modelFile }.joined(separator: ", ")
            print("[ModelRegistry] embedder-exclusion smoke FAILED — embedder(s) registered as LLM: \(names)")
            assertionFailure("Embedder GGUF leaked into availableModels: \(names)")
        }
    }
    #endif

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

            // Embedding-only GGUFs (e.g. nomic-embed-text) live in the same
            // Resources/Models dir as the generator since ADR-0011 PR-A. They must
            // never be registered as selectable LLMs — drop them before they reach
            // `modelSpecs` / `availableModels` / the model picker.
            if Self.looksLikeEmbedder(fileName: fileName, metadata: metadata) {
                print("[ModelRegistry] Skipping embedder GGUF (not a generator): \(fileName)")
                return
            }

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

    /// Get standard model search paths (sandbox-safe, container-only)
    private func getModelSearchPaths() -> [String] {
        let fileManager = FileManager.default
        var paths: [String] = []

        // App bundle resources (read-only, always allowed)
        if let resourcePath = Bundle.main.resourcePath {
            paths.append(resourcePath)
            paths.append("\(resourcePath)/Models")
            paths.append("\(resourcePath)/Resources/Models")
        }

        // App container directories (sandbox-safe)
        #if os(iOS)
        // iOS: Use container directories
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            paths.append(appSupport.appendingPathComponent("Models").path)
            paths.append(appSupport.appendingPathComponent("NoesisNoema/models").path)
        }
        if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            paths.append(documents.appendingPathComponent("Models").path)
        }
        #elseif os(macOS)
        // macOS: Use container directories only
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            paths.append(appSupport.appendingPathComponent("NoesisNoema/models").path)
        }
        // Application-scoped documents (if using App Sandbox)
        if let documentsURL = try? fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            paths.append(documentsURL.appendingPathComponent("Models").path)
        }
        #endif

        // NOTE: Removed ~/Downloads, ~/Documents/Models - these require explicit user permission
        // Use NSOpenPanel or security-scoped bookmarks to access user-selected files outside container

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
