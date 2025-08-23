// Project: NoesisNoema
// File: TestRunner.swift
// Created by Copilot on 2025/08/23
// Description: Simple test runner for model registry functionality
// License: MIT License

import Foundation

/// Simple test runner that can be executed from CLI
class TestRunner {
    
    /// Run all tests and return exit code
    static func runAllTests() async -> Int {
        print("🧪 NoesisNoema Model Registry Test Suite")
        print(String(repeating: "=", count: 50))
        
        var allTestsPassed = true
        
        // Test 1: OOM-safe defaults
        print("\n🔬 Test 1: OOM-Safe Defaults")
        allTestsPassed = testOOMSafeDefaults() && allTestsPassed
        
        // Test 2: Model spec auto-tuning
        print("\n🔬 Test 2: ModelSpec Auto-Tuning")
        allTestsPassed = testModelSpecAutoTuning() && allTestsPassed
        
        // Test 3: GGUF reader validation
        print("\n🔬 Test 3: GGUF Reader Validation")
        allTestsPassed = testGGUFReaderValidation() && allTestsPassed
        
        // Test 4: Model registry functionality
        print("\n🔬 Test 4: Model Registry")
        allTestsPassed = await testModelRegistry() && allTestsPassed
        
        // Test 5: CLI model information formatting
        print("\n🔬 Test 5: CLI Model Information")
        allTestsPassed = await testCLIModelInfo() && allTestsPassed
        
        // Test 6: Runtime parameter optimization
        print("\n🔬 Test 6: Runtime Parameter Optimization")
        allTestsPassed = testRuntimeParameterOptimization() && allTestsPassed
        
        // Summary
        print("\n" + String(repeating: "=", count: 50))
        if allTestsPassed {
            print("✅ All tests passed!")
            return 0
        } else {
            print("❌ Some tests failed!")
            return 1
        }
    }
    
    /// Test OOM-safe defaults
    private static func testOOMSafeDefaults() -> Bool {
        do {
            let params = RuntimeParams.oomSafeDefaults()
            
            // Basic validation
            guard params.nThreads > 0 && params.nThreads <= 16 else {
                print("❌ Invalid thread count: \(params.nThreads)")
                return false
            }
            
            guard params.nCtx >= 1024 && params.nCtx <= 32768 else {
                print("❌ Invalid context size: \(params.nCtx)")
                return false
            }
            
            guard params.nBatch > 0 && params.nBatch <= 2048 else {
                print("❌ Invalid batch size: \(params.nBatch)")
                return false
            }
            
            guard params.memoryLimitMB > 512 else {
                print("❌ Memory limit too low: \(params.memoryLimitMB)")
                return false
            }
            
            guard params.temperature > 0 && params.temperature <= 2.0 else {
                print("❌ Invalid temperature: \(params.temperature)")
                return false
            }
            
            print("✅ OOM-safe defaults are valid")
            print("   Threads: \(params.nThreads), Context: \(params.nCtx), Batch: \(params.nBatch)")
            print("   Memory limit: \(params.memoryLimitMB) MB")
            return true
            
        } catch {
            print("❌ Error testing OOM-safe defaults: \(error)")
            return false
        }
    }
    
    /// Test model spec auto-tuning
    private static func testModelSpecAutoTuning() -> Bool {
        do {
            // Test small model (4B)
            let smallMetadata = GGUFMetadata(
                architecture: "qwen",
                parameterCount: 4.0,
                contextLength: 32768,
                modelSizeBytes: 2_500_000_000, // 2.5GB
                quantization: "Q4_K_M",
                layerCount: 32,
                embeddingDimension: 2048
            )
            
            let smallSpec = ModelSpec.withAutoTunedParams(
                id: "test-small",
                name: "Test Small",
                modelFile: "test-small.gguf",
                version: "4B",
                metadata: smallMetadata
            )
            
            // Test large model (20B)
            let largeMetadata = GGUFMetadata(
                architecture: "gpt",
                parameterCount: 20.0,
                contextLength: 4096,
                modelSizeBytes: 12_000_000_000, // 12GB
                quantization: "Q4_K_S",
                layerCount: 44,
                embeddingDimension: 6144
            )
            
            let largeSpec = ModelSpec.withAutoTunedParams(
                id: "test-large",
                name: "Test Large",
                modelFile: "test-large.gguf",
                version: "20B",
                metadata: largeMetadata
            )
            
            // Validate auto-tuning worked correctly
            guard largeSpec.runtimeParams.nBatch <= smallSpec.runtimeParams.nBatch else {
                print("❌ Large model should have smaller or equal batch size")
                return false
            }
            
            guard smallSpec.tags.contains("small") else {
                print("❌ Small model should have 'small' tag")
                return false
            }
            
            guard largeSpec.tags.contains("large") else {
                print("❌ Large model should have 'large' tag")
                return false
            }
            
            print("✅ Model auto-tuning working correctly")
            print("   Small model batch: \(smallSpec.runtimeParams.nBatch)")
            print("   Large model batch: \(largeSpec.runtimeParams.nBatch)")
            return true
            
        } catch {
            print("❌ Error testing model spec auto-tuning: \(error)")
            return false
        }
    }
    
    /// Test GGUF reader validation
    private static func testGGUFReaderValidation() -> Bool {
        // Test invalid file
        let isValid = GGUFReader.isValidGGUFFile(at: "/tmp/nonexistent.gguf")
        guard !isValid else {
            print("❌ Non-existent file should not be valid")
            return false
        }
        
        // Test with empty path
        let emptyPathValid = GGUFReader.isValidGGUFFile(at: "")
        guard !emptyPathValid else {
            print("❌ Empty path should not be valid")
            return false
        }
        
        print("✅ GGUF reader validation working")
        return true
    }
    
    /// Test model registry functionality
    private static func testModelRegistry() async -> Bool {
        let registry = ModelRegistry.shared
        
        // Get all specs
        let allSpecs = await registry.getAllModelSpecs()
        guard !allSpecs.isEmpty else {
            print("❌ Registry should have predefined models")
            return false
        }
        
        // Test finding specific model
        let janModel = await registry.getModelSpec(id: "jan-v1-4b")
        guard let jan = janModel else {
            print("❌ Should find Jan model")
            return false
        }
        
        guard jan.name == "Jan-V1-4B" else {
            print("❌ Jan model name mismatch: \(jan.name)")
            return false
        }
        
        // Test finding by tag
        let qwenModels = await registry.findModelSpecs(withTag: "qwen")
        guard !qwenModels.isEmpty else {
            print("❌ Should find models with qwen tag")
            return false
        }
        
        // Test finding by architecture
        let llamaModels = await registry.findModelSpecs(withArchitecture: "llama")
        guard !llamaModels.isEmpty else {
            print("❌ Should find models with llama architecture")
            return false
        }
        
        print("✅ Model registry functionality working")
        print("   Total models: \(allSpecs.count)")
        print("   Qwen models: \(qwenModels.count)")
        print("   LLaMA models: \(llamaModels.count)")
        return true
    }
    
    /// Test CLI model information formatting
    private static func testCLIModelInfo() async -> Bool {
        let registry = ModelRegistry.shared
        
        guard let modelInfo = await registry.getModelInfo(id: "jan-v1-4b") else {
            print("❌ Should get model info for Jan model")
            return false
        }
        
        // Check that info contains expected sections
        let requiredSections = [
            "Model ID:",
            "Name:",
            "Architecture:",
            "Parameters:",
            "Runtime Parameters:",
            "Tags:",
            "Description:"
        ]
        
        for section in requiredSections {
            guard modelInfo.contains(section) else {
                print("❌ Model info missing section: \(section)")
                return false
            }
        }
        
        print("✅ CLI model information formatting working")
        return true
    }
    
    /// Test runtime parameter optimization
    private static func testRuntimeParameterOptimization() -> Bool {
        let baseParams = RuntimeParams.oomSafeDefaults()
        
        // Test with different model sizes
        let smallModel = GGUFMetadata(
            architecture: "phi3",
            parameterCount: 3.8,
            contextLength: 4096,
            modelSizeBytes: 2_000_000_000,
            quantization: "Q4_K_M"
        )
        
        let largeModel = GGUFMetadata(
            architecture: "llama",
            parameterCount: 70.0,
            contextLength: 4096,
            modelSizeBytes: 40_000_000_000,
            quantization: "Q4_K_M"
        )
        
        let smallParams = ModelSpec.autoTuneParameters(metadata: smallModel, baseParams: baseParams)
        let largeParams = ModelSpec.autoTuneParameters(metadata: largeModel, baseParams: baseParams)
        
        // Large model should have more conservative settings
        guard largeParams.nBatch <= smallParams.nBatch else {
            print("❌ Large model should have smaller batch size")
            return false
        }
        
        guard largeParams.nGpuLayers <= smallParams.nGpuLayers else {
            print("❌ Large model should have fewer GPU layers")
            return false
        }
        
        print("✅ Runtime parameter optimization working")
        print("   Small model batch: \(smallParams.nBatch), GPU layers: \(smallParams.nGpuLayers)")
        print("   Large model batch: \(largeParams.nBatch), GPU layers: \(largeParams.nGpuLayers)")
        return true
    }
}