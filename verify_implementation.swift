#!/usr/bin/env swift

// Simple verification script for the ModelRegistry implementation
// This can be run independently to test the core functionality

import Foundation

// MARK: - Basic Runtime Parameters Test
struct TestRuntimeParams {
    static func test() {
        print("Testing RuntimeParams.oomSafeDefaults()...")
        
        let params = RuntimeParams.oomSafeDefaults()
        
        // Verify basic constraints
        assert(params.nThreads > 0, "nThreads should be positive")
        assert(params.nCtx > 0, "nCtx should be positive") 
        assert(params.nBatch > 0, "nBatch should be positive")
        assert(params.memoryLimitMB > 0, "memoryLimitMB should be positive")
        assert(params.temperature > 0, "temperature should be positive")
        assert(params.topK > 0, "topK should be positive")
        assert(params.topP > 0 && params.topP <= 1.0, "topP should be between 0 and 1")
        
        print("✅ RuntimeParams basic validation passed")
        print("   Generated params: threads=\(params.nThreads), ctx=\(params.nCtx), batch=\(params.nBatch), mem=\(params.memoryLimitMB)MB")
    }
}

// MARK: - Basic Model Spec Test
struct TestModelSpec {
    static func test() {
        print("\nTesting ModelSpec creation...")
        
        let metadata = GGUFMetadata(
            architecture: "test",
            parameterCount: 7.0,
            contextLength: 4096,
            modelSizeBytes: 4_000_000_000,
            quantization: "Q4_K_M"
        )
        
        let spec = ModelSpec.withAutoTunedParams(
            id: "test-model",
            name: "Test Model",
            modelFile: "test.gguf",
            version: "7B",
            metadata: metadata
        )
        
        assert(spec.id == "test-model", "ID should match")
        assert(spec.name == "Test Model", "Name should match")
        assert(spec.metadata.parameterCount == 7.0, "Parameter count should match")
        assert(spec.runtimeParams.nCtx <= metadata.contextLength, "Context should not exceed model limit")
        
        print("✅ ModelSpec creation passed")
        print("   Model: \(spec.name) (\(spec.id))")
        print("   Runtime params: ctx=\(spec.runtimeParams.nCtx), batch=\(spec.runtimeParams.nBatch)")
    }
}

// MARK: - GGUF Reader Test
struct TestGGUFReader {
    static func test() {
        print("\nTesting GGUFReader...")
        
        // Test file validation with non-existent file
        let isValid = GGUFReader.isValidGGUFFile(at: "/tmp/nonexistent.gguf")
        assert(!isValid, "Non-existent file should not be valid")
        
        print("✅ GGUFReader validation passed")
    }
}

// MARK: - Main Test Runner
print("🧪 Running NoesisNoema ModelRegistry Verification Tests")
print("=" + String(repeating: "=", count: 60))

TestRuntimeParams.test()
TestModelSpec.test()
TestGGUFReader.test()

print("\n✅ All verification tests passed!")
print("The ModelRegistry implementation is working correctly.")