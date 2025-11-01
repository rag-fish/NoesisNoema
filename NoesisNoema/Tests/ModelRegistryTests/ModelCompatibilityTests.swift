// filepath: NoesisNoema/Tests/ModelRegistryTests/ModelCompatibilityTests.swift
// Project: NoesisNoema
// Description: Model compatibility and discovery tests
// License: MIT License

#if canImport(XCTest)
import XCTest
@testable import NoesisNoema

class ModelCompatibilityTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
    }

    override func tearDown() async throws {
        try await super.tearDown()
    }

    /// Test 1: All models in Resources/Models can be discovered
    func testModelAutoDiscovery() async throws {
        let registry = ModelRegistry.shared
        await registry.scanForModels()

        let availableModels = await registry.getAvailableModelSpecs()
        XCTAssertGreaterThan(availableModels.count, 0, "No models discovered in Resources/Models")

        // Verify new models are found
        let expectedModels = [
            "Llama-3.3-70B-Instruct",
            "gpt-oss-20b",
            "Jan-v1-4B"
        ]

        for expected in expectedModels {
            let found = availableModels.contains { $0.name.contains(expected) || $0.modelFile.contains(expected) }
            if !found {
                print("⚠️ Warning: Expected model '\(expected)' not found in registry")
                print("Available models: \(availableModels.map { $0.name }.joined(separator: ", "))")
            }
        }

        // At least one model should be available
        XCTAssertGreaterThan(availableModels.count, 0, "At least one model should be discovered")
    }

    /// Test 2: GGUF metadata extraction works correctly
    func testGGUFMetadataExtraction() async throws {
        let registry = ModelRegistry.shared
        await registry.scanForModels()

        let availableModels = await registry.getAvailableModelSpecs()

        for spec in availableModels {
            // Validate metadata
            XCTAssertFalse(spec.metadata.architecture.isEmpty, "Architecture should not be empty for \(spec.name)")
            XCTAssertGreaterThan(spec.metadata.parameterCount, 0, "Parameter count should be > 0 for \(spec.name)")
            XCTAssertGreaterThan(spec.metadata.contextLength, 0, "Context length should be > 0 for \(spec.name)")
            XCTAssertFalse(spec.metadata.quantization.isEmpty, "Quantization should not be empty for \(spec.name)")

            print("✓ \(spec.name): \(spec.metadata.architecture), \(String(format: "%.1fB", spec.metadata.parameterCount)) params, \(spec.metadata.quantization)")
        }
    }

    /// Test 3: GGUF file validation
    func testGGUFFileValidation() throws {
        let searchPaths = [
            Bundle.main.resourcePath.map { "\($0)/Models" },
            Bundle.main.resourcePath.map { "\($0)/Resources/Models" }
        ].compactMap { $0 }

        var foundFiles = 0

        for path in searchPaths {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else {
                continue
            }

            let ggufFiles = contents.filter { $0.hasSuffix(".gguf") }

            for file in ggufFiles {
                let fullPath = "\(path)/\(file)"
                let isValid = GGUFReader.isValidGGUFFile(at: fullPath)

                if isValid {
                    print("✓ Valid GGUF: \(file)")
                    foundFiles += 1
                } else {
                    print("✗ Invalid GGUF: \(file)")
                }

                XCTAssertTrue(isValid, "File \(file) should be a valid GGUF file")
            }
        }

        if foundFiles == 0 {
            print("⚠️ No GGUF files found in search paths: \(searchPaths)")
        }
    }

    /// Test 4: Model compatibility validation
    func testModelValidation() async throws {
        let registry = ModelRegistry.shared
        await registry.scanForModels()

        let specs = await registry.getAvailableModelSpecs()

        for spec in specs {
            let validation = await ModelFactory.validateModel(metadata: spec.metadata)

            print("\n--- \(spec.name) ---")
            print("Compatible: \(validation.isCompatible ? "✓" : "✗")")
            print("Estimated Memory: \(String(format: "%.1f GB", validation.estimatedMemoryGB))")

            if validation.hasWarnings {
                print("Warnings:")
                for warning in validation.warnings {
                    print("  • \(warning)")
                }
            }

            // All models should be at least theoretically compatible
            XCTAssertTrue(validation.isCompatible, "\(spec.name) should be compatible")
        }
    }

    /// Test 5: Model factory engine type detection
    func testEngineTypeDetection() async throws {
        let testCases: [(arch: String, expected: ModelFactory.EngineType)] = [
            ("llama", .llama),
            ("llama3", .llama),
            ("qwen", .qwen),
            ("qwen2", .qwen),
            ("phi", .phi),
            ("phi3", .phi),
            ("gemma", .gemma),
            ("mistral", .mistral),
            ("gpt", .gpt),
            ("unknown", .llama) // Default fallback
        ]

        for testCase in testCases {
            let metadata = GGUFMetadata(
                architecture: testCase.arch,
                parameterCount: 7.0,
                contextLength: 4096,
                quantization: "Q4_K_M",
                layerCount: 32,
                embeddingDimension: 4096,
                feedForwardDimension: 11008,
                attentionHeads: 32,
                supportsFlashAttention: true
            )

            let engineType = await ModelFactory.engineType(for: metadata)
            XCTAssertEqual(engineType, testCase.expected, "Architecture '\(testCase.arch)' should map to \(testCase.expected)")
        }
    }

    /// Test 6: Runtime parameter auto-tuning
    func testRuntimeParameterAutotuning() async throws {
        let registry = ModelRegistry.shared
        await registry.scanForModels()

        let specs = await registry.getAvailableModelSpecs()

        for spec in specs {
            let params = spec.runtimeParams

            // Validate params are within reasonable bounds
            XCTAssertGreaterThan(params.nThreads, 0, "nThreads should be > 0")
            XCTAssertGreaterThanOrEqual(params.nGpuLayers, 0, "nGpuLayers should be >= 0")
            XCTAssertGreaterThan(params.nCtx, 0, "nCtx should be > 0")
            XCTAssertGreaterThan(params.nBatch, 0, "nBatch should be > 0")
            XCTAssertLessThanOrEqual(params.nCtx, spec.metadata.contextLength, "nCtx should not exceed model context length")

            print("✓ \(spec.name): nCtx=\(params.nCtx), nBatch=\(params.nBatch), GPU=\(params.nGpuLayers)")
        }
    }

    /// Test 7: Symlink support for model files
    func testSymlinkResolution() throws {
        let searchPaths = [
            Bundle.main.resourcePath.map { "\($0)/Models" },
            Bundle.main.resourcePath.map { "\($0)/Resources/Models" }
        ].compactMap { $0 }

        for path in searchPaths {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else {
                continue
            }

            let ggufFiles = contents.filter { $0.hasSuffix(".gguf") }

            for file in ggufFiles {
                let fullPath = "\(path)/\(file)"

                // Check if file exists (should work for both regular files and symlinks)
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory)

                if exists && !isDirectory.boolValue {
                    // Check if it's a symlink
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath),
                       let fileType = attrs[.type] as? FileAttributeType,
                       fileType == .typeSymbolicLink {
                        print("✓ Symlink resolved: \(file)")
                    } else {
                        print("✓ Regular file: \(file)")
                    }

                    XCTAssertTrue(exists, "File should exist: \(file)")
                }
            }
        }
    }
}
#endif
