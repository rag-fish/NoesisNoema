#if !BRIDGE_TEST
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
        
        // Test 7: Registry JSON Loader (validation)
        print("\n🔬 Test 7: Registry JSON Loader Validation")
        allTestsPassed = testRegistryJSONLoader() && allTestsPassed
        
        // Test 8: M1 Max Autotune Case
        print("\n🔬 Test 8: M1 Max Autotune Case")
        allTestsPassed = testM1MaxAutotune() && allTestsPassed

        // Test 9: Autotune cache hit speed
        print("\n🔬 Test 9: Autotune Cache Hit")
        allTestsPassed = await testAutotuneCacheHit() && allTestsPassed

        // Test 10: Autotune timeout fallback
        print("\n🔬 Test 10: Autotune Timeout Fallback")
        allTestsPassed = await testAutotuneTimeoutFallback() && allTestsPassed

        // Test 11: Unknown quantization fallback
        print("\n🔬 Test 11: Unknown Quantization Fallback")
        allTestsPassed = await testUnknownQuantFallback() && allTestsPassed

        // Test 12: Persistence across restart
        print("\n🔬 Test 12: Persistence Across Restart")
        allTestsPassed = await testPersistenceAcrossRestart() && allTestsPassed

        // Test 13: Reset restores recommended
        print("\n🔬 Test 13: Reset Restores Recommended")
        allTestsPassed = await testResetRestoresRecommended() && allTestsPassed
        
        // Test 14: Corrupted GGUF metadata should error
        print("\n🔬 Test 14: Corrupted GGUF Metadata Error")
        allTestsPassed = await testCorruptedGGUFMetadataError() && allTestsPassed
        
        // Test 15: M2 Pro Autotune Case
        print("\n🔬 Test 15: M2 Pro Autotune Case")
        allTestsPassed = testM2ProAutotune() && allTestsPassed
        
        // Test 16: LocalRetriever duplicate suppression and trace
        print("\n🔬 Test 16: LocalRetriever Duplicate Suppression + Trace")
        allTestsPassed = testLocalRetrieverDuplicateSuppressionAndTrace() && allTestsPassed
        
        // Test 17: ParamBandit initializes and updates via RewardBus
        print("\n🔬 Test 17: ParamBandit Init + Reward Updates")
        #if !BRIDGE_TEST
        allTestsPassed = testParamBanditInitAndUpdates() && allTestsPassed
        #else
        print("(skipped under BRIDGE_TEST)")
        #endif
        
        // Test 18: ParamBandit converges with synthetic rewards
        print("\n🔬 Test 18: ParamBandit Convergence (synthetic)")
        #if !BRIDGE_TEST
        allTestsPassed = testParamBanditConvergence() && allTestsPassed
        #else
        print("(skipped under BRIDGE_TEST)")
        #endif
        
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
    }
    
    /// Test model spec auto-tuning
    private static func testModelSpecAutoTuning() -> Bool {
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
    
    /// Test registry.json loader and validation
    private static func testRegistryJSONLoader() -> Bool {
        // Malformed: missing 'models'
        let badTopLevel = "{" + "\"foo\": []" + "}"
        do {
            _ = try RegistryJSONLoader.load(from: badTopLevel)
            print("❌ Loader should fail when 'models' is missing")
            return false
        } catch { /* expected */ }
        
        // Entry not object
        let badEntry = "[1,2,3]"
        do {
            _ = try RegistryJSONLoader.load(from: badEntry)
            print("❌ Loader should fail when entry is not an object")
            return false
        } catch { /* expected */ }
        
        // Minimal valid
        let ok = "{" +
        "\"models\":[{" +
        "\"id\":\"llama3-8b\"," +
        "\"name\":\"Llama 3 8B\"," +
        "\"model_file\":\"llama3-8b.Q4_K_M.gguf\"," +
        "\"version\":\"8B\"," +
        "\"quantization\":\"Q4_K_M\"" +
        "}]" +
        "}"
        do {
            let specs = try RegistryJSONLoader.load(from: ok)
            guard specs.count == 1, specs[0].id == "llama3-8b" else {
                print("❌ Minimal valid registry did not parse as expected")
                return false
            }
        } catch {
            print("❌ Loader failed on minimal valid registry: \(error)")
            return false
        }
        
        print("✅ Registry JSON loader validation working")
        return true
    }
    
    /// Test M1 Max hardware case autotune
    private static func testM1MaxAutotune() -> Bool {
        // Construct a fake M1 Max profile (Darwin/arm64, unified memory 64GB)
        let hw = HardwareProfile(os: "Darwin", arch: "arm64", cpuCores: 10, memTotalGB: 64.0, vramTotalGB: 64.0, gpuVendor: "Apple", soc: "Apple M1 Max")
        let base = RuntimeParams.oomSafeDefaults()
        let meta = GGUFMetadata(
            architecture: "qwen",
            parameterCount: 4.0,
            contextLength: 32768,
            modelSizeBytes: 2_500_000_000,
            quantization: "Q4_K_M"
        )
        let tuned = ModelSpec.autoTuneParameters(metadata: meta, baseParams: base, hardware: hw)
        // Expectations: high threads, GPU layers suggested > 4, context respected <= 32768
        guard tuned.nThreads >= 4 && tuned.nThreads <= 12 else {
            print("❌ Unexpected thread count for M1 Max: \(tuned.nThreads)")
            return false
        }
        guard tuned.nGpuLayers >= 4 else {
            print("❌ Expected some GPU layers on M1 Max, got \(tuned.nGpuLayers)")
            return false
        }
        guard tuned.nCtx <= meta.contextLength else {
            print("❌ Context exceeds model capability")
            return false
        }
        print("✅ M1 Max autotune behaves as expected (nGpuLayers=\(tuned.nGpuLayers))")
        return true
    }

    /// Corrupted GGUF file should produce an error
    private static func testCorruptedGGUFMetadataError() async -> Bool {
        let tmp = URL(fileURLWithPath: "/tmp/nn_bad_\(UUID().uuidString).gguf")
        do {
            // Write wrong magic
            try Data("NOTG".utf8).write(to: tmp)
        } catch {
            print("❌ Failed to create temp corrupted file: \(error)")
            return false
        }
        defer { try? FileManager.default.removeItem(at: tmp) }
        
        // Quick validity check
        let valid = GGUFReader.isValidGGUFFile(at: tmp.path)
        guard !valid else {
            print("❌ Corrupted file should not be valid")
            return false
        }
        
        // Read should throw invalidGGUFFile
        do {
            _ = try await GGUFReader.readMetadata(from: tmp.path)
            print("❌ Expected GGUFReader to throw for corrupted file")
            return false
        } catch {
            if let e = error as? GGUFReader.GGUFError {
                switch e {
                case .invalidGGUFFile:
                    print("✅ Corrupted GGUF produced invalidGGUFFile as expected")
                    return true
                default:
                    print("❌ Unexpected GGUFError: \(e)")
                    return false
                }
            } else {
                print("❌ Unexpected error type: \(error)")
                return false
            }
        }
    }

    /// Test M2 Pro hardware autotune
    private static func testM2ProAutotune() -> Bool {
        // Approx M2 Pro profile (arm64, 32GB unified memory)
        let hw = HardwareProfile(os: "Darwin", arch: "arm64", cpuCores: 12, memTotalGB: 32.0, vramTotalGB: 32.0, gpuVendor: "Apple", soc: "Apple M2 Pro")
        let base = RuntimeParams.oomSafeDefaults()
        let meta = GGUFMetadata(
            architecture: "llama",
            parameterCount: 8.0,
            contextLength: 8192,
            modelSizeBytes: 4_600_000_000,
            quantization: "Q4_K_M"
        )
        let tuned = ModelSpec.autoTuneParameters(metadata: meta, baseParams: base, hardware: hw)
        // For 32GB VRAM, computeGpuLayers suggests >= 20 (actually 30). Ensure reasonable bound
        guard tuned.nGpuLayers >= 20 else {
            print("❌ Expected >=20 GPU layers on M2 Pro, got \(tuned.nGpuLayers)")
            return false
        }
        guard tuned.nCtx <= meta.contextLength else {
            print("❌ Context exceeds model capability on M2 Pro")
            return false
        }
        print("✅ M2 Pro autotune behaves as expected (nGpuLayers=\(tuned.nGpuLayers))")
        return true
    }

    /// Test 9: Autotune cache hit should return quickly (<100ms)
    private static func testAutotuneCacheHit() async -> Bool {
        let base = RuntimeParams.oomSafeDefaults()
        var spec = ModelSpec(
            id: "cache-test",
            name: "Cache Test",
            modelFile: "dummy.gguf",
            version: "X",
            metadata: GGUFMetadata(architecture: "llama", parameterCount: 8.0, contextLength: 4096, modelSizeBytes: 1_000_000_000, quantization: "Q4_K_M"),
            runtimeParams: base,
            isAvailable: true,
            filePath: "/tmp/dummy.gguf",
            tags: [],
            description: ""
        )

        // First run: populate the cache with injected deterministic key
        let injectedHasher: () async throws -> String = { return "hash123" }
        let injectedDevice: () -> String = { return "arm64-mem64.0-vram64.0" }
        let (p1, out1) = await AutotuneService.shared.recommendForTest(spec: spec, base: base, timeoutSeconds: 3.0, trace: false, injectedHasher: injectedHasher, injectedDeviceId: injectedDevice)
        spec.runtimeParams = p1
        guard out1.cacheHit == false else {
            print("❌ First run should not be a cache hit")
            return false
        }

        // Second run: same key => cache hit, measure time
        let start = Date()
        let (_, out2) = await AutotuneService.shared.recommendForTest(spec: spec, base: base, timeoutSeconds: 3.0, trace: false, injectedHasher: injectedHasher, injectedDeviceId: injectedDevice)
        let elapsed = Date().timeIntervalSince(start)
        guard out2.cacheHit else {
            print("❌ Second run should be a cache hit")
            return false
        }
        guard elapsed < 0.1 else {
            print(String(format: "❌ Cache hit too slow: %.0f ms", elapsed * 1000))
            return false
        }
        print(String(format: "✅ Cache hit in %.0f ms", elapsed * 1000))
        return true
    }

    /// Test 10: Autotune timeout fallback
    private static func testAutotuneTimeoutFallback() async -> Bool {
        let base = RuntimeParams.oomSafeDefaults()
        let spec = ModelSpec(
            id: "timeout-test",
            name: "Timeout Test",
            modelFile: "dummy.gguf",
            version: "X",
            metadata: GGUFMetadata(architecture: "llama", parameterCount: 8.0, contextLength: 4096, modelSizeBytes: 1_000_000_000, quantization: "Q4_K_M"),
            runtimeParams: base,
            isAvailable: false,
            filePath: nil,
            tags: [],
            description: ""
        )
        // Inject a slow hasher to force timeout
        let slowHasher: () async throws -> String = {
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
            return "slowhash"
        }
        let dev: () -> String = { return "arm64-mem64.0-vram64.0" }
        let (_, out) = await AutotuneService.shared.recommendForTest(spec: spec, base: base, timeoutSeconds: 0.2, trace: false, injectedHasher: slowHasher, injectedDeviceId: dev)
        guard out.timedOut && out.usedFallback else {
            print("❌ Expected timeout fallback (timedOut && usedFallback)")
            return false
        }
        print("✅ Timeout produced conservative fallback as expected")
        return true
    }

    /// Test 11: Unknown quantization should trigger conservative fallback
    private static func testUnknownQuantFallback() async -> Bool {
        let base = RuntimeParams.oomSafeDefaults()
        let meta = GGUFMetadata(architecture: "llama", parameterCount: 8.0, contextLength: 4096, modelSizeBytes: 1_000_000_000, quantization: "XYZ_UNK")
        let spec = ModelSpec(id: "unkq", name: "UnkQ", modelFile: "unk.gguf", version: "X", metadata: meta, runtimeParams: base, isAvailable: false, filePath: nil)
        let (params, out) = await AutotuneService.shared.recommendForTest(spec: spec, base: base, timeoutSeconds: 1.0, trace: false, injectedHasher: { "h" }, injectedDeviceId: { "d" })
        guard out.usedFallback && !out.timedOut && !out.cacheHit else {
            print("❌ Expected unknown-quant fallback without timeout/cacheHit")
            return false
        }
        // Ensure context not exceeding model max
        guard params.nCtx <= meta.contextLength else {
            print("❌ nCtx exceeds model max after fallback")
            return false
        }
        print("✅ Unknown quantization fallback applied")
        return true
    }

    /// Test 12: Settings persist after restart (simulated via cache clear)
    private static func testPersistenceAcrossRestart() async -> Bool {
        // Use isolated temp directory
        let tmpDir = URL(fileURLWithPath: "/tmp/nn_persist_\(UUID().uuidString)", isDirectory: true)
        RegistryPersistence.baseDirectoryOverride = tmpDir
        await RegistryPersistence.shared.wipe()
        await RegistryPersistence.shared.clearCache()
        
        // Prepare a model id and two distinct params
        let modelId = "jan-v1-4b"
        var recommended = RuntimeParams.oomSafeDefaults()
        recommended.nCtx = 4096
        var overrideP = recommended
        overrideP.nCtx = 1024
        
        // Save a record
        await RegistryPersistence.shared.updateRecord(modelId: modelId) { rec in
            rec = ModelRuntimeRecord(recommended: recommended, overrideParams: overrideP, mode: .override)
        }
        await RegistryPersistence.shared.setLastSelectedModel(id: modelId)
        
        // Simulate restart: clear cache then load
        await RegistryPersistence.shared.clearCache()
        guard let rec = await RegistryPersistence.shared.getRecord(for: modelId) else {
            print("❌ Failed to load persisted record")
            return false
        }
        guard let last = await RegistryPersistence.shared.getLastSelectedModelId(), last == modelId else {
            print("❌ Last selected model id not persisted correctly")
            return false
        }
        guard rec.mode == .override, let ov = rec.overrideParams, ov.nCtx == 1024, rec.recommended.nCtx == 4096 else {
            print("❌ Persisted fields mismatch (mode/override/recommended)")
            return false
        }
        print("✅ Persistence works across restart (simulated)")
        return true
    }

    /// Test 13: Reset should switch to recommended and keep value
    private static func testResetRestoresRecommended() async -> Bool {
        let tmpDir = URL(fileURLWithPath: "/tmp/nn_persist_\(UUID().uuidString)", isDirectory: true)
        RegistryPersistence.baseDirectoryOverride = tmpDir
        await RegistryPersistence.shared.wipe()
        await RegistryPersistence.shared.clearCache()
        
        let modelId = "llama-3-8b"
        var recommended = RuntimeParams.oomSafeDefaults()
        recommended.nCtx = 2048
        var overrideP = recommended
        overrideP.nCtx = 512
        
        await RegistryPersistence.shared.updateRecord(modelId: modelId) { rec in
            rec = ModelRuntimeRecord(recommended: recommended, overrideParams: overrideP, mode: .override)
        }
        // Reset behavior: set mode to recommended
        await RegistryPersistence.shared.updateRecord(modelId: modelId) { rec in
            if rec == nil { rec = ModelRuntimeRecord(recommended: recommended, overrideParams: nil, mode: .recommended) }
            else { rec!.mode = .recommended }
        }
        await RegistryPersistence.shared.clearCache()
        guard let rec = await RegistryPersistence.shared.getRecord(for: modelId) else {
            print("❌ Failed to reload record after reset")
            return false
        }
        guard rec.mode == .recommended && rec.recommended.nCtx == 2048 else {
            print("❌ Reset did not restore recommended values")
            return false
        }
        print("✅ Reset switches back to recommended")
        return true
    }

    /// Test 16: LocalRetriever duplicate suppression and trace
    private static func testLocalRetrieverDuplicateSuppressionAndTrace() -> Bool {
        // Prepare demo corpus with duplicates
        VectorStore.shared.clear()
        let docs = [
            "Swift is a powerful and intuitive programming language for iOS and macOS.",
            "Swift is a powerful and intuitive programming language for iOS and macOS.", // duplicate
            "BM25 is a ranking function used in search engines.",
            "Embeddings map text to vectors in a semantic space.",
            "MMR balances relevance and diversity for reranking.",
            "Apple's M2 chips have unified memory."
        ]
        VectorStore.shared.addTexts(docs, deduplicate: false) // allow duplicates in store
        
        let retriever = LocalRetriever(store: .shared)
        let results = retriever.retrieve(query: "swift programming", k: 4, lambda: 0.7, trace: true)
        guard !results.isEmpty else {
            print("❌ Retriever returned no results")
            return false
        }
        // Ensure duplicate suppression by content
        let contents = results.map { $0.content }
        let uniqueCount = Set(contents).count
        guard uniqueCount == contents.count else {
            print("❌ Duplicate contents present in results: \(contents)")
            return false
        }
        print("✅ Duplicate suppression OK (results=\(results.count))")
        return true
    }
}

// MARK: - ParamBandit Tests
extension TestRunner {
    /// Bandit initializes with α=1,β=1 and updates on RewardBus events
    fileprivate static func testParamBanditInitAndUpdates() -> Bool {
        // Deterministic RNG for stability
        var seq: [Double] = Array(repeating: 0.6, count: 100)
        var idx = 0
        let rng: () -> Double = { defer { idx += 1 }; return seq[min(idx, seq.count-1)] }
        
        let arms = [
            ParamBandit.Arm(id: "A", params: RetrievalParams(topK: 4, mmrLambda: 0.7, minScore: 0.1)),
            ParamBandit.Arm(id: "B", params: RetrievalParams(topK: 6, mmrLambda: 0.5, minScore: 0.2))
        ]
        let bandit = ParamBandit(config: .init(arms: arms), rewardBus: RewardBus.shared, urand: rng)
        let qa1 = UUID()
        let (cluster, _) = bandit.chooseParams(for: "hello world", qaId: qa1)
        // Priors should be 1/1 for each arm in this cluster
        let st = bandit.state(cluster: cluster)
        for a in arms {
            guard let ab = st[a.id], ab.alpha == 1 && ab.beta == 1 else {
                print("❌ wrong or missing priors for arm \(a.id): \(String(describing: st[a.id]))")
                return false
            }
        }
        // Publish reward for chosen arm (alpha increment)
        let qa2 = UUID()
        let chosen = bandit.chooseParams(for: "hello world", qaId: qa2).arm.id
        RewardBus.shared.publish(qaId: qa2, verdict: .up, tags: [])
        usleep(50_000)
        let st2 = bandit.state(cluster: cluster)
        guard let ab2 = st2[chosen], ab2.alpha == 2 && ab2.beta == 1 else {
            print("❌ expected alpha increment for arm \(chosen), got \(String(describing: st2[chosen]))")
            return false
        }
        print("✅ Priors + RewardBus update OK (arm=\(chosen))")
        return true
    }
    
    /// With synthetic rewards favoring one arm, TS should pick it more often
    fileprivate static func testParamBanditConvergence() -> Bool {
        // RNG cycling for coverage
        var base: [Double] = (0..<1000).map { _ in Double.random(in: 0..<1) }
        var i = 0
        let rng: () -> Double = { defer { i += 1 }; return base[i % base.count] }
        let arms = [
            ParamBandit.Arm(id: "good", params: RetrievalParams(topK: 5, mmrLambda: 0.7, minScore: 0.1)),
            ParamBandit.Arm(id: "bad", params: RetrievalParams(topK: 5, mmrLambda: 0.5, minScore: 0.2))
        ]
        let bandit = ParamBandit(config: .init(arms: arms), rewardBus: RewardBus.shared, urand: rng)
        let cluster = bandit.chooseParams(for: "topic: swift mmr bandit").cluster
        var picks: [String:Int] = [:]
        for _ in 0..<300 {
            let qa = UUID()
            let choice = bandit.chooseParams(for: "topic: swift mmr bandit", qaId: qa).arm.id
            picks[choice, default: 0] += 1
            let reward: Bool = (choice == "good") ? (Double.random(in: 0..<1) < 0.7) : (Double.random(in: 0..<1) < 0.3)
            RewardBus.shared.publish(qaId: qa, verdict: reward ? .up : .down, tags: [])
        }
        usleep(120_000)
        let good = picks["good", default: 0]
        let bad = picks["bad", default: 0]
        guard good > bad else {
            print("❌ TS did not prefer better arm (good=\(good), bad=\(bad))")
            return false
        }
        let st = bandit.state(cluster: cluster)
        guard let abGood = st["good"], abGood.alpha > abGood.beta else {
            print("❌ Posterior for good arm not improved: \(String(describing: st["good"]))")
            return false
        }
        print("✅ Convergence trend OK (good=\(good), bad=\(bad))")
        return true
    }
}
#endif
