// Project: NoesisNoema
// File: ModelRegistryTests.swift
// Created by Copilot on 2025/08/23
// Description: Tests for the model registry and auto-tuning functionality
// License: MIT License

import Foundation

/// Simple test runner for the model registry functionality
class ModelRegistryTests {
    
    static func runTests() async {
        print("Running ModelRegistry Tests...")
        print("=" * 50)
        
        await testOOMSafeDefaults()
        await testModelSpecCreation()
        await testModelRegistry()
        await testGGUFReader()
        
        print("All tests completed!")
    }
    
    /// Test OOM-safe defaults
    static func testOOMSafeDefaults() async {
        print("\n🔬 Testing OOM-safe defaults...")
        
        let params = RuntimeParams.oomSafeDefaults()
        
        assert(params.nThreads > 0, "nThreads should be positive")
        assert(params.nCtx > 0, "nCtx should be positive")
        assert(params.nBatch > 0, "nBatch should be positive")
        assert(params.memoryLimitMB > 0, "memoryLimitMB should be positive")
        assert(params.temperature > 0 && params.temperature <= 2.0, "temperature should be reasonable")
        assert(params.topK > 0, "topK should be positive")
        assert(params.topP > 0 && params.topP <= 1.0, "topP should be between 0 and 1")
        
        print("✅ OOM-safe defaults are valid")
        print("   - Threads: \(params.nThreads)")
        print("   - Context: \(params.nCtx)")
        print("   - Batch: \(params.nBatch)")
        print("   - Memory limit: \(params.memoryLimitMB) MB")
        print("   - GPU layers: \(params.nGpuLayers)")
    }
    
    /// Test ModelSpec creation and auto-tuning
    static func testModelSpecCreation() async {
        print("\n🔬 Testing ModelSpec creation...")
        
        let metadata = GGUFMetadata(
            architecture: "llama",
            parameterCount: 7.0,
            contextLength: 4096,
            modelSizeBytes: 4_000_000_000, // 4GB
            quantization: "Q4_K_M",
            vocabSize: 32000,
            layerCount: 32,
            embeddingDimension: 4096,
            feedForwardDimension: 11008,
            attentionHeads: 32,
            supportsFlashAttention: true
        )
        
        let spec = ModelSpec.withAutoTunedParams(
            id: "test-model",
            name: "Test Model",
            modelFile: "test.gguf",
            version: "7B",
            metadata: metadata
        )
        
        assert(spec.id == "test-model", "Model ID should match")
        assert(spec.name == "Test Model", "Model name should match")
        assert(spec.metadata.architecture == "llama", "Architecture should match")
        assert(spec.runtimeParams.nCtx <= metadata.contextLength, "Context should not exceed model capability")
        assert(spec.tags.contains("llama"), "Should have architecture tag")
        assert(spec.tags.contains("medium"), "Should have size tag for 7B model")
        
        print("✅ ModelSpec creation successful")
        print("   - ID: \(spec.id)")
        print("   - Context: \(spec.runtimeParams.nCtx)")
        print("   - Batch: \(spec.runtimeParams.nBatch)")
        print("   - Tags: \(spec.tags.joined(separator: ", "))")
    }
    
    /// Test ModelRegistry functionality
    static func testModelRegistry() async {
        print("\n🔬 Testing ModelRegistry...")
        
        let registry = ModelRegistry.shared
        let initialSpecs = await registry.getAllModelSpecs()
        
        assert(!initialSpecs.isEmpty, "Registry should have predefined models")
        
        // Test finding by ID
        let janModel = await registry.getModelSpec(id: "jan-v1-4b")
        assert(janModel != nil, "Should find Jan model by ID")
        assert(janModel?.name == "Jan-V1-4B", "Jan model name should match")
        
        // Test finding by tag
        let qwenModels = await registry.findModelSpecs(withTag: "qwen")
        assert(!qwenModels.isEmpty, "Should find models with qwen tag")
        
        // Test finding by architecture
        let llamaModels = await registry.findModelSpecs(withArchitecture: "llama")
        assert(!llamaModels.isEmpty, "Should find models with llama architecture")
        
        print("✅ ModelRegistry functionality working")
        print("   - Total models: \(initialSpecs.count)")
        print("   - Qwen models: \(qwenModels.count)")
        print("   - LLaMA models: \(llamaModels.count)")
    }
    
    /// Test GGUF reader validation
    static func testGGUFReader() async {
        print("\n🔬 Testing GGUFReader...")
        
        // Test with non-existent file
        let isValid = GGUFReader.isValidGGUFFile(at: "/non/existent/file.gguf")
        assert(!isValid, "Non-existent file should not be valid")
        
        // Test error handling for non-existent file
        do {
            _ = try await GGUFReader.readMetadata(from: "/non/existent/file.gguf")
            assert(false, "Should throw error for non-existent file")
        } catch {
            assert(error is GGUFReader.GGUFError, "Should throw GGUFError")
        }
        
        print("✅ GGUFReader error handling working")
    }
}

/// String repetition operator for test formatting
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}