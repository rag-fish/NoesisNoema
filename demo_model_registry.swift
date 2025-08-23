#!/usr/bin/env swift

// Demonstration script for the NoesisNoema Model Registry
// This shows how the new auto-tuning system works

import Foundation

print("🚀 NoesisNoema Model Registry Demonstration")
print(String(repeating: "=", count: 60))

// 1. Show OOM-safe defaults
print("\n📊 OOM-Safe Defaults based on your system:")
let params = RuntimeParams.oomSafeDefaults()
print("   CPU Cores: \(ProcessInfo.processInfo.processorCount)")
print("   Total Memory: \(String(format: "%.1f GB", Double(ProcessInfo.processInfo.physicalMemory) / (1024*1024*1024)))")
print("   → Recommended Threads: \(params.nThreads)")
print("   → Context Size: \(params.nCtx)")
print("   → Batch Size: \(params.nBatch)")
print("   → Memory Limit: \(params.memoryLimitMB) MB")
print("   → GPU Layers: \(params.nGpuLayers)")

// 2. Show model specs with auto-tuning
print("\n🧠 Example Model Specifications:")

let exampleModels = [
    (
        "Small Model (Phi-3 Mini)",
        GGUFMetadata(
            architecture: "phi3",
            parameterCount: 3.8,
            contextLength: 4096,
            modelSizeBytes: 2_200_000_000,
            quantization: "Q4_K_M",
            layerCount: 32,
            embeddingDimension: 3072
        )
    ),
    (
        "Medium Model (LLaMA-3 8B)",
        GGUFMetadata(
            architecture: "llama",
            parameterCount: 8.0,
            contextLength: 8192,
            modelSizeBytes: 4_600_000_000,
            quantization: "Q4_K_M",
            layerCount: 32,
            embeddingDimension: 4096
        )
    ),
    (
        "Large Model (GPT-OSS 20B)",
        GGUFMetadata(
            architecture: "gpt",
            parameterCount: 20.0,
            contextLength: 4096,
            modelSizeBytes: 12_000_000_000,
            quantization: "Q4_K_S",
            layerCount: 44,
            embeddingDimension: 6144
        )
    )
]

for (name, metadata) in exampleModels {
    let autoParams = ModelSpec.autoTuneParameters(metadata: metadata, baseParams: params)
    
    print("\n   \(name):")
    print("     Parameters: \(String(format: "%.1fB", metadata.parameterCount))")
    print("     File Size: \(String(format: "%.1f GB", Double(metadata.modelSizeBytes) / (1024*1024*1024)))")
    print("     Auto-tuned Settings:")
    print("       - Context: \(autoParams.nCtx) (max: \(metadata.contextLength))")
    print("       - Batch: \(autoParams.nBatch)")
    print("       - GPU Layers: \(autoParams.nGpuLayers)")
    print("       - Memory Limit: \(autoParams.memoryLimitMB) MB")
}

// 3. Show predefined model registry
print("\n📋 Predefined Model Registry:")
Task {
    let registry = ModelRegistry.shared
    let allSpecs = await registry.getAllModelSpecs()
    
    for spec in allSpecs.prefix(3) {
        print("\n   \(spec.name) (\(spec.id)):")
        print("     Architecture: \(spec.metadata.architecture)")
        print("     Parameters: \(String(format: "%.1fB", spec.metadata.parameterCount))")
        print("     Quantization: \(spec.metadata.quantization)")
        print("     Tags: \(spec.tags.joined(separator: ", "))")
        print("     Runtime: ctx=\(spec.runtimeParams.nCtx), batch=\(spec.runtimeParams.nBatch)")
    }
    
    print("\n💡 Key Benefits:")
    print("   ✅ Automatic parameter tuning based on GGUF metadata")
    print("   ✅ OOM-safe defaults prevent memory crashes")
    print("   ✅ Device-specific optimization (iOS vs macOS)")
    print("   ✅ Model size-aware batch sizing")
    print("   ✅ Quantization-aware memory management")
    
    print("\n🔧 CLI Usage Examples:")
    print("   nn model list                    # List available models")
    print("   nn model info jan-v1-4b         # Show detailed model info")
    print("   nn model scan /path/to/models    # Scan for GGUF files")
    print("   nn model test                    # Run functionality tests")
    
    print("\n✨ The ModelRegistry automatically:")
    print("   • Scans standard directories for GGUF files")
    print("   • Reads model metadata to determine optimal settings")
    print("   • Provides OOM-safe defaults based on your hardware")
    print("   • Manages model specifications centrally")
    
    exit(0)
}

dispatchMain()