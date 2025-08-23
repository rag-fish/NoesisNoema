// Project: NoesisNoema
// File: ModelSpec.swift
// Created by Copilot on 2025/08/23
// Description: Model specification and runtime parameters for GGUF auto-tuning
// License: MIT License

import Foundation

/// Runtime parameters for model inference
struct RuntimeParams: Codable, Sendable {
    /// Number of threads for inference
    var nThreads: Int32
    
    /// Number of GPU layers to offload
    var nGpuLayers: Int32
    
    /// Context window size
    var nCtx: UInt32
    
    /// Batch size for processing
    var nBatch: UInt32
    
    /// Maximum number of tokens to generate
    var nPredict: Int32
    
    /// Sampling temperature
    var temperature: Float
    
    /// Top-K sampling parameter
    var topK: Int32
    
    /// Top-P sampling parameter
    var topP: Float
    
    /// Random seed for generation
    var seed: UInt64
    
    /// Memory allocation limit in MB (0 = unlimited)
    var memoryLimitMB: UInt64
    
    /// Whether to use memory mapping
    var useMemoryMapping: Bool
    
    /// Flash attention support
    var useFlashAttention: Bool
    
    init(
        nThreads: Int32 = 4,
        nGpuLayers: Int32 = 0,
        nCtx: UInt32 = 2048,
        nBatch: UInt32 = 512,
        nPredict: Int32 = 256,
        temperature: Float = 0.7,
        topK: Int32 = 40,
        topP: Float = 0.9,
        seed: UInt64 = 1234,
        memoryLimitMB: UInt64 = 0,
        useMemoryMapping: Bool = true,
        useFlashAttention: Bool = false
    ) {
        self.nThreads = nThreads
        self.nGpuLayers = nGpuLayers
        self.nCtx = nCtx
        self.nBatch = nBatch
        self.nPredict = nPredict
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
        self.seed = seed
        self.memoryLimitMB = memoryLimitMB
        self.useMemoryMapping = useMemoryMapping
        self.useFlashAttention = useFlashAttention
    }
    
    /// Creates OOM-safe defaults based on available system memory
    static func oomSafeDefaults() -> RuntimeParams {
        let processInfo = ProcessInfo.processInfo
        let totalMemoryGB = Double(processInfo.physicalMemory) / (1024 * 1024 * 1024)
        
        // Conservative defaults based on available memory
        let nCtx: UInt32
        let nBatch: UInt32
        let memoryLimitMB: UInt64
        let nGpuLayers: Int32
        
        #if os(iOS)
        // iOS devices - more conservative defaults
        if totalMemoryGB >= 8.0 {
            nCtx = 4096
            nBatch = 512
            memoryLimitMB = 2048 // 2GB limit
            nGpuLayers = 999 // Use GPU acceleration when available
        } else if totalMemoryGB >= 6.0 {
            nCtx = 2048
            nBatch = 256
            memoryLimitMB = 1536 // 1.5GB limit
            nGpuLayers = 64
        } else {
            nCtx = 1024
            nBatch = 128
            memoryLimitMB = 1024 // 1GB limit
            nGpuLayers = 32
        }
        #else
        // macOS devices - more generous defaults
        if totalMemoryGB >= 16.0 {
            nCtx = 8192
            nBatch = 1024
            memoryLimitMB = 4096 // 4GB limit
            nGpuLayers = 999
        } else if totalMemoryGB >= 8.0 {
            nCtx = 4096
            nBatch = 512
            memoryLimitMB = 2048 // 2GB limit
            nGpuLayers = 80
        } else {
            nCtx = 2048
            nBatch = 256
            memoryLimitMB = 1024 // 1GB limit
            nGpuLayers = 40
        }
        #endif
        
        // Thread count based on CPU cores
        let coreCount = processInfo.processorCount
        let nThreads = Int32(max(1, min(coreCount - 1, 8))) // Leave one core free, max 8 threads
        
        return RuntimeParams(
            nThreads: nThreads,
            nGpuLayers: nGpuLayers,
            nCtx: nCtx,
            nBatch: nBatch,
            nPredict: 256,
            temperature: 0.7,
            topK: 40,
            topP: 0.9,
            seed: UInt64.random(in: 0...UInt64.max),
            memoryLimitMB: memoryLimitMB,
            useMemoryMapping: true,
            useFlashAttention: false
        )
    }
}

/// GGUF metadata extracted from model files
struct GGUFMetadata: Codable, Sendable {
    /// Model architecture (e.g., "llama", "qwen", "phi")
    var architecture: String
    
    /// Number of parameters in billions
    var parameterCount: Double
    
    /// Context length supported by the model
    var contextLength: UInt32
    
    /// Model size in bytes
    var modelSizeBytes: UInt64
    
    /// Quantization type (e.g., "Q4_K_M", "Q8_0")
    var quantization: String
    
    /// Vocabulary size
    var vocabSize: UInt32
    
    /// Number of layers
    var layerCount: UInt32
    
    /// Embedding dimension
    var embeddingDimension: UInt32
    
    /// Feed-forward dimension
    var feedForwardDimension: UInt32
    
    /// Number of attention heads
    var attentionHeads: UInt32
    
    /// Whether the model supports flash attention
    var supportsFlashAttention: Bool
    
    init(
        architecture: String = "unknown",
        parameterCount: Double = 0.0,
        contextLength: UInt32 = 2048,
        modelSizeBytes: UInt64 = 0,
        quantization: String = "unknown",
        vocabSize: UInt32 = 32000,
        layerCount: UInt32 = 32,
        embeddingDimension: UInt32 = 4096,
        feedForwardDimension: UInt32 = 11008,
        attentionHeads: UInt32 = 32,
        supportsFlashAttention: Bool = false
    ) {
        self.architecture = architecture
        self.parameterCount = parameterCount
        self.contextLength = contextLength
        self.modelSizeBytes = modelSizeBytes
        self.quantization = quantization
        self.vocabSize = vocabSize
        self.layerCount = layerCount
        self.embeddingDimension = embeddingDimension
        self.feedForwardDimension = feedForwardDimension
        self.attentionHeads = attentionHeads
        self.supportsFlashAttention = supportsFlashAttention
    }
}

/// Complete model specification including metadata and optimized parameters
struct ModelSpec: Codable, Sendable, Identifiable {
    /// Unique identifier for the model
    let id: String
    
    /// Human-readable name
    let name: String
    
    /// Model file name
    let modelFile: String
    
    /// Model version
    let version: String
    
    /// GGUF metadata extracted from the model file
    var metadata: GGUFMetadata
    
    /// Optimized runtime parameters for this model
    var runtimeParams: RuntimeParams
    
    /// Whether this model is currently available
    var isAvailable: Bool
    
    /// File path where the model is located
    var filePath: String?
    
    /// Tags for categorizing the model
    var tags: [String]
    
    /// Description of the model
    var description: String
    
    init(
        id: String,
        name: String,
        modelFile: String,
        version: String,
        metadata: GGUFMetadata = GGUFMetadata(),
        runtimeParams: RuntimeParams = RuntimeParams.oomSafeDefaults(),
        isAvailable: Bool = false,
        filePath: String? = nil,
        tags: [String] = [],
        description: String = ""
    ) {
        self.id = id
        self.name = name
        self.modelFile = modelFile
        self.version = version
        self.metadata = metadata
        self.runtimeParams = runtimeParams
        self.isAvailable = isAvailable
        self.filePath = filePath
        self.tags = tags
        self.description = description
    }
    
    /// Creates a model spec with auto-tuned parameters based on GGUF metadata
    static func withAutoTunedParams(
        id: String,
        name: String,
        modelFile: String,
        version: String,
        metadata: GGUFMetadata,
        filePath: String? = nil
    ) -> ModelSpec {
        let baseParams = RuntimeParams.oomSafeDefaults()
        let tunedParams = autoTuneParameters(metadata: metadata, baseParams: baseParams)
        
        return ModelSpec(
            id: id,
            name: name,
            modelFile: modelFile,
            version: version,
            metadata: metadata,
            runtimeParams: tunedParams,
            isAvailable: filePath != nil,
            filePath: filePath,
            tags: generateTags(metadata: metadata),
            description: generateDescription(metadata: metadata)
        )
    }
    
    /// Auto-tune runtime parameters based on model metadata and system capabilities
    static func autoTuneParameters(metadata: GGUFMetadata, baseParams: RuntimeParams) -> RuntimeParams {
        var params = baseParams
        
        // Adjust context length based on model's capability
        params.nCtx = min(params.nCtx, metadata.contextLength)
        
        // Adjust batch size based on model size
        if metadata.parameterCount > 20.0 {
            // Large models (>20B parameters) - reduce batch size
            params.nBatch = min(params.nBatch, 256)
            params.nGpuLayers = min(params.nGpuLayers, 40) // Conservative GPU offloading
        } else if metadata.parameterCount > 7.0 {
            // Medium models (7-20B parameters)
            params.nBatch = min(params.nBatch, 512)
            params.nGpuLayers = min(params.nGpuLayers, 80)
        }
        // Small models (<7B) keep default settings
        
        // Adjust based on quantization
        switch metadata.quantization {
        case let q where q.contains("Q2"):
            // Lower quality quantization - can use larger batch
            params.nBatch = min(params.nBatch * 2, 1024)
        case let q where q.contains("Q8") || q.contains("Q6"):
            // Higher quality quantization - reduce batch to fit in memory
            params.nBatch = max(params.nBatch / 2, 128)
        default:
            break
        }
        
        // Enable flash attention if supported
        params.useFlashAttention = metadata.supportsFlashAttention
        
        // Set memory limit based on model size with safety margin
        let modelSizeMB = metadata.modelSizeBytes / (1024 * 1024)
        let recommendedMemory = modelSizeMB * 2 // 2x model size for safety
        if params.memoryLimitMB == 0 || params.memoryLimitMB > recommendedMemory {
            params.memoryLimitMB = recommendedMemory
        }
        
        return params
    }
    
    /// Generate appropriate tags based on model metadata
    private static func generateTags(metadata: GGUFMetadata) -> [String] {
        var tags: [String] = []
        
        // Architecture tag
        tags.append(metadata.architecture.lowercased())
        
        // Size category
        if metadata.parameterCount >= 20.0 {
            tags.append("large")
        } else if metadata.parameterCount >= 7.0 {
            tags.append("medium")
        } else {
            tags.append("small")
        }
        
        // Quantization tag
        tags.append(metadata.quantization.lowercased())
        
        // Context length category
        if metadata.contextLength >= 8192 {
            tags.append("long-context")
        } else if metadata.contextLength >= 4096 {
            tags.append("medium-context")
        } else {
            tags.append("short-context")
        }
        
        return tags
    }
    
    /// Generate a description based on model metadata
    private static func generateDescription(metadata: GGUFMetadata) -> String {
        let paramStr = String(format: "%.1fB", metadata.parameterCount)
        let sizeStr = String(format: "%.1f GB", Double(metadata.modelSizeBytes) / (1024 * 1024 * 1024))
        
        return "\(metadata.architecture.capitalized) architecture with \(paramStr) parameters, \(metadata.quantization) quantization, \(sizeStr) file size, \(metadata.contextLength) context length"
    }
}