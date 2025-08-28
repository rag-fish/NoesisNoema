// Project: NoesisNoema
// File: GGUFReader.swift
// Created by Copilot on 2025/08/23
// Description: GGUF file metadata reader for auto-tuning model parameters
// License: MIT License

import Foundation
import llama

/// GGUF file reader for extracting model metadata
class GGUFReader {

    /// Error types for GGUF reading operations
    enum GGUFError: Error, LocalizedError {
        case fileNotFound(String)
        case invalidGGUFFile(String)
        case readError(String)
        case keyNotFound(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "GGUF file not found at path: \(path)"
            case .invalidGGUFFile(let path):
                return "Invalid GGUF file format: \(path)"
            case .readError(let message):
                return "Error reading GGUF file: \(message)"
            case .keyNotFound(let key):
                return "Required key not found in GGUF metadata: \(key)"
            }
        }
    }

    /// Read GGUF metadata from a file path
    static func readMetadata(from filePath: String) async throws -> GGUFMetadata {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let metadata = try readMetadataSync(from: filePath)
                    continuation.resume(returning: metadata)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Synchronous version of metadata reading
    private static func readMetadataSync(from filePath: String) throws -> GGUFMetadata {
        // Check if file exists
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw GGUFError.fileNotFound(filePath)
        }

        // Initialize GGUF context with no_alloc=true to avoid loading tensor data
        var initParams = gguf_init_params()
        initParams.no_alloc = true
        initParams.ctx = nil

        // Load GGUF file
        guard let ggufContext = gguf_init_from_file(filePath, initParams) else {
            throw GGUFError.invalidGGUFFile(filePath)
        }

        defer {
            gguf_free(ggufContext)
        }

        // Get file size
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: filePath)
        let modelSizeBytes = fileAttributes[.size] as? UInt64 ?? 0

        // Extract metadata using helper functions
        let architecture = try getString(from: ggufContext, key: "general.architecture", defaultValue: "unknown")
        let contextLength = try getUInt32(from: ggufContext, key: "\(architecture).context_length", defaultValue: 2048)
        let vocabSize = try getUInt32(from: ggufContext, key: "\(architecture).vocab_size", defaultValue: 32000)
        let layerCount = try getUInt32(from: ggufContext, key: "\(architecture).block_count", defaultValue: 32)
        let embeddingDimension = try getUInt32(from: ggufContext, key: "\(architecture).embedding_length", defaultValue: 4096)
        let feedForwardDimension = try getUInt32(from: ggufContext, key: "\(architecture).feed_forward_length", defaultValue: 11008)
        let attentionHeads = try getUInt32(from: ggufContext, key: "\(architecture).attention.head_count", defaultValue: 32)

        // Estimate parameter count based on architecture and dimensions
        let parameterCount = estimateParameterCount(
            architecture: architecture,
            layers: layerCount,
            embeddingDim: embeddingDimension,
            ffDim: feedForwardDimension,
            vocabSize: vocabSize
        )

        // Detect quantization from filename or metadata
        let quantization = detectQuantization(from: filePath, ggufContext: ggufContext)

        // Check flash attention support (architecture-dependent)
        let supportsFlashAttention = checkFlashAttentionSupport(architecture: architecture)

        return GGUFMetadata(
            architecture: architecture,
            parameterCount: parameterCount,
            contextLength: contextLength,
            modelSizeBytes: modelSizeBytes,
            quantization: quantization,
            vocabSize: vocabSize,
            layerCount: layerCount,
            embeddingDimension: embeddingDimension,
            feedForwardDimension: feedForwardDimension,
            attentionHeads: attentionHeads,
            supportsFlashAttention: supportsFlashAttention
        )
    }

    /// Get string value from GGUF context
    private static func getString(from context: OpaquePointer, key: String, defaultValue: String) throws -> String {
        let keyCount = gguf_get_n_kv(context)

        for i in 0..<keyCount {
            guard let keyPtr = gguf_get_key(context, i) else { continue }
            let currentKey = String(cString: keyPtr)

            if currentKey == key {
                let valueType = gguf_get_kv_type(context, i)
                if valueType == GGUF_TYPE_STRING {
                    guard let valuePtr = gguf_get_val_str(context, i) else {
                        return defaultValue
                    }
                    return String(cString: valuePtr)
                }
            }
        }

        return defaultValue
    }

    /// Get UInt32 value from GGUF context
    private static func getUInt32(from context: OpaquePointer, key: String, defaultValue: UInt32) throws -> UInt32 {
        let keyCount = gguf_get_n_kv(context)

        for i in 0..<keyCount {
            guard let keyPtr = gguf_get_key(context, i) else { continue }
            let currentKey = String(cString: keyPtr)

            if currentKey == key {
                let valueType = gguf_get_kv_type(context, i)
                switch valueType {
                case GGUF_TYPE_UINT32:
                    return gguf_get_val_u32(context, i)
                case GGUF_TYPE_INT32:
                    let val = gguf_get_val_i32(context, i)
                    return val >= 0 ? UInt32(val) : defaultValue
                case GGUF_TYPE_UINT64:
                    let val = gguf_get_val_u64(context, i)
                    return UInt32(min(val, UInt64(UInt32.max)))
                case GGUF_TYPE_INT64:
                    let val = gguf_get_val_i64(context, i)
                    return val >= 0 ? UInt32(min(UInt64(val), UInt64(UInt32.max))) : defaultValue
                default:
                    break
                }
            }
        }

        return defaultValue
    }

    /// Estimate parameter count based on model architecture
    private static func estimateParameterCount(
        architecture: String,
        layers: UInt32,
        embeddingDim: UInt32,
        ffDim: UInt32,
        vocabSize: UInt32
    ) -> Double {
        let layersF = Double(layers)
        let embeddingDimF = Double(embeddingDim)
        let ffDimF = Double(ffDim)
        let vocabSizeF = Double(vocabSize)

        // Token embeddings: vocab_size * embedding_dim
        let embeddingParams = vocabSizeF * embeddingDimF

        // Per-layer parameters (approximate)
        var layerParams: Double = 0

        switch architecture.lowercased() {
        case "llama", "llama2":
            // Self-attention: 4 * embedding_dim^2 (Q, K, V, O projections)
            let attentionParams = 4.0 * embeddingDimF * embeddingDimF
            // Feed-forward: 3 * embedding_dim * ff_dim (gate, up, down)
            let ffParams = 3.0 * embeddingDimF * ffDimF
            // Layer norms: 2 * embedding_dim
            let normParams = 2.0 * embeddingDimF

            layerParams = attentionParams + ffParams + normParams

        case "qwen", "qwen2":
            // Similar to LLaMA but with some variations
            let attentionParams = 4.0 * embeddingDimF * embeddingDimF
            let ffParams = 3.0 * embeddingDimF * ffDimF
            let normParams = 2.0 * embeddingDimF

            layerParams = attentionParams + ffParams + normParams

        case "phi", "phi3":
            // Phi models have different architecture
            let attentionParams = 4.0 * embeddingDimF * embeddingDimF
            let ffParams = 2.0 * embeddingDimF * ffDimF // Different FF structure
            let normParams = 2.0 * embeddingDimF

            layerParams = attentionParams + ffParams + normParams

        default:
            // Generic estimation
            let attentionParams = 4.0 * embeddingDimF * embeddingDimF
            let ffParams = 3.0 * embeddingDimF * ffDimF
            let normParams = 2.0 * embeddingDimF

            layerParams = attentionParams + ffParams + normParams
        }

        // Total parameters
        let totalParams = embeddingParams + layersF * layerParams + embeddingDimF // final norm

        // Convert to billions
        return totalParams / 1_000_000_000.0
    }

    /// Detect quantization type from filename or metadata
    private static func detectQuantization(from filePath: String, ggufContext: OpaquePointer) -> String {
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent

        // Try to detect from filename first
        let quantPatterns = [
            "Q2_K", "Q3_K_S", "Q3_K_M", "Q3_K_L", "Q4_0", "Q4_1",
            "Q4_K_S", "Q4_K_M", "Q5_0", "Q5_1", "Q5_K_S", "Q5_K_M",
            "Q6_K", "Q8_0", "F16", "F32"
        ]

        for pattern in quantPatterns {
            if fileName.uppercased().contains(pattern) {
                return pattern
            }
        }

        // Try to get from GGUF metadata
        if let quantFromMetadata = try? getString(from: ggufContext, key: "general.quantization_version", defaultValue: "") {
            if !quantFromMetadata.isEmpty {
                return quantFromMetadata
            }
        }

        return "unknown"
    }

    /// Check if architecture supports flash attention
    private static func checkFlashAttentionSupport(architecture: String) -> Bool {
        switch architecture.lowercased() {
        case "llama", "llama2", "qwen", "qwen2":
            return true
        case "phi", "phi3":
            return true
        default:
            return false
        }
    }

    /// Quickly check if a file is a valid GGUF file without full parsing
    static func isValidGGUFFile(at path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else {
            return false
        }

        guard let fileHandle = FileHandle(forReadingAtPath: path) else {
            return false
        }

        defer {
            fileHandle.closeFile()
        }

        // Read first 4 bytes to check magic number
        let magicData = fileHandle.readData(ofLength: 4)
        guard magicData.count == 4 else {
            return false
        }

        // GGUF magic number is "GGUF" (0x47474955)
        let magic = String(data: magicData, encoding: .ascii)
        return magic == "GGUF"
    }
}
