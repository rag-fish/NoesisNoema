// filepath: NoesisNoema/ModelRegistry/Core/ModelFactory.swift
// Project: NoesisNoema
// Description: Model factory for dynamic inference engine instantiation
// License: MIT License

import Foundation

/// Factory for creating appropriate inference engines based on model metadata
actor ModelFactory {

    /// Supported engine types (all currently route through llama.cpp)
    enum EngineType: String {
        case llama      // Llama, Llama2, Llama3
        case qwen       // Qwen, Qwen2
        case phi        // Phi, Phi2, Phi3
        case gemma      // Gemma
        case mistral    // Mistral
        case gpt        // GPT architectures

        var description: String {
            switch self {
            case .llama: return "LLaMA-based models"
            case .qwen: return "Qwen-based models"
            case .phi: return "Phi-based models"
            case .gemma: return "Gemma-based models"
            case .mistral: return "Mistral-based models"
            case .gpt: return "GPT-based models"
            }
        }
    }

    /// Determine engine type from model metadata
    static func engineType(for metadata: GGUFMetadata) -> EngineType {
        let arch = metadata.architecture.lowercased()

        // Pattern matching for architecture detection
        if arch.contains("llama") { return .llama }
        if arch.contains("qwen") { return .qwen }
        if arch.contains("phi") { return .phi }
        if arch.contains("gemma") { return .gemma }
        if arch.contains("mistral") { return .mistral }
        if arch.contains("gpt") { return .gpt }

        // Default fallback to llama (most compatible)
        SystemLog().logEvent(event: "[ModelFactory] Unknown architecture '\(arch)', defaulting to llama")
        return .llama
    }

    /// Create appropriate inference engine for a model
    /// - Parameters:
    ///   - modelPath: Full path to GGUF model file
    ///   - metadata: Extracted GGUF metadata
    ///   - runtimeParams: Tuned runtime parameters
    /// - Returns: Initialized inference engine
    /// - Throws: InferenceError if engine creation fails
    static func createEngine(
        modelPath: String,
        metadata: GGUFMetadata,
        runtimeParams: RuntimeParams
    ) async throws -> any InferenceEngine {
        let engineType = engineType(for: metadata)

        SystemLog().logEvent(event: "[ModelFactory] Creating \(engineType.rawValue) engine for \(metadata.architecture)")

        // All current architectures are supported by llama.cpp
        // Future: Add specialized engines for specific architectures if needed
        switch engineType {
        case .llama, .qwen, .phi, .gemma, .mistral, .gpt:
            do {
                let engine = try await LlamaInferenceEngine(
                    modelPath: modelPath,
                    metadata: metadata,
                    runtimeParams: runtimeParams
                )

                SystemLog().logEvent(event: "[ModelFactory] ✓ Engine created: \(metadata.architecture) (\(String(format: "%.1fB", metadata.parameterCount)) params)")
                return engine
            } catch {
                SystemLog().logEvent(event: "[ModelFactory] ✗ Failed to create engine: \(error)")
                throw InferenceError.contextInitializationFailed
            }
        }
    }

    /// Validate model compatibility before loading
    /// - Parameter metadata: Model metadata to validate
    /// - Returns: Validation result with warnings if any
    static func validateModel(metadata: GGUFMetadata) -> ModelValidationResult {
        var warnings: [String] = []
        var isCompatible = true

        // Check parameter count against hardware
        let hwProfile = HardwareProbe.probe()
        let estimatedMemoryGB = metadata.parameterCount * 0.6 // Rough estimate for Q4 models

        if estimatedMemoryGB > hwProfile.memTotalGB * 0.8 {
            warnings.append("Model may exceed available memory (requires ~\(String(format: "%.1f", estimatedMemoryGB))GB)")
        }

        // Check context length
        if metadata.contextLength > 32768 {
            warnings.append("Very large context window (\(metadata.contextLength)) may impact performance")
        }

        // Check quantization
        let knownQuantizations = ["Q2_K", "Q3_K_S", "Q3_K_M", "Q3_K_L",
                                  "Q4_0", "Q4_1", "Q4_K_S", "Q4_K_M", "Q4_K_XL",
                                  "Q5_0", "Q5_1", "Q5_K_S", "Q5_K_M",
                                  "Q6_K", "Q8_0", "F16", "F32"]
        if !knownQuantizations.contains(metadata.quantization) {
            warnings.append("Unknown quantization format: \(metadata.quantization)")
        }

        // Large models on iOS
        #if os(iOS)
        if metadata.parameterCount > 8.0 {
            warnings.append("Large model on iOS - expect reduced performance")
        }
        #endif

        return ModelValidationResult(
            isCompatible: isCompatible,
            warnings: warnings,
            estimatedMemoryGB: estimatedMemoryGB
        )
    }
}

/// Result of model validation
struct ModelValidationResult: Sendable {
    let isCompatible: Bool
    let warnings: [String]
    let estimatedMemoryGB: Double

    var hasWarnings: Bool { !warnings.isEmpty }

    var description: String {
        var desc = isCompatible ? "✓ Compatible" : "✗ Incompatible"
        if !warnings.isEmpty {
            desc += "\nWarnings:\n" + warnings.map { "  • \($0)" }.joined(separator: "\n")
        }
        return desc
    }
}
