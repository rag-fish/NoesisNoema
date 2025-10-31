
21800# ModelRegistry Refactoring Plan
## Noesis Noema - Dynamic GGUF Model Architecture

### Executive Summary

**Current Status**: ✅ Modern architecture already in place
**llama.cpp Original Bindings**: ❌ Unused/Dead code
**Custom Swift Wrapper**: ✅ Fully functional and isolated
**ModelRegistry**: ✅ Implemented with auto-discovery

---

## Phase 1: Dead Code Cleanup ⚠️

### 1.1 Remove Unused llama.cpp Bindings

```bash
# Safe to delete - not referenced anywhere in active code
rm -rf NoesisNoema/externals/llama.cpp.bak
```

**Files to be removed:**
- `externals/llama.cpp.bak/examples/llama.swiftui/llama.swiftui/llama_swiftuiApp.swift`
- `externals/llama.cpp.bak/examples/llama.swiftui/llama.cpp.swift/LibLlama.swift`
- `externals/llama.cpp.bak/examples/llama.swiftui/llama.swiftui/Models/LlamaState.swift`

### 1.2 Clean Xcode Project Build Settings

Remove obsolete framework search paths from `project.pbxproj`:
- `$(PROJECT_DIR)/NoesisNoema/externals/llama.cpp/build-ios-sim/**`
- `$(PROJECT_DIR)/NoesisNoema/externals/llama.cpp.bak/build-ios-sim/**`

**Action**: Manual cleanup in Xcode Build Settings → Framework Search Paths

---

## Phase 2: ModelRegistry Enhancements 🚀

### 2.1 Enhanced GGUF Introspection

**Current**: GGUFReader uses heuristics (filename-based detection)
**Enhancement**: Add true GGUF header parsing for accurate metadata

**Implementation:**

```swift
// GGUFReader.swift - Add binary header parsing
extension GGUFReader {
    /// Parse GGUF magic number and version
    static func parseGGUFHeader(from filePath: String) throws -> GGUFHeader {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
        defer { try? handle.close() }

        // Read GGUF magic: 0x46554747 ("GGUF" in little-endian)
        guard let magicData = try? handle.read(upToCount: 4),
              magicData.count == 4 else {
            throw GGUFError.invalidGGUFFile(filePath)
        }

        let magic = magicData.withUnsafeBytes { $0.load(as: UInt32.self) }
        guard magic == 0x46554747 else {
            throw GGUFError.invalidGGUFFile(filePath)
        }

        // Read version (uint32)
        guard let versionData = try? handle.read(upToCount: 4) else {
            throw GGUFError.readError("Failed to read version")
        }
        let version = versionData.withUnsafeBytes { $0.load(as: UInt32.self) }

        return GGUFHeader(magic: magic, version: version)
    }

    /// Parse GGUF key-value metadata
    static func parseGGUFMetadata(from filePath: String) throws -> [String: GGUFValue] {
        // Implementation: Parse GGUF metadata section
        // - Read tensor count, KV count
        // - Parse key-value pairs with type information
        // - Extract architecture, parameters, quantization from metadata
    }
}

struct GGUFHeader {
    let magic: UInt32
    let version: UInt32
}

enum GGUFValue {
    case uint8(UInt8)
    case int8(Int8)
    case uint16(UInt16)
    case int16(Int16)
    case uint32(UInt32)
    case int32(Int32)
    case float32(Float)
    case bool(Bool)
    case string(String)
    case array([GGUFValue])
}
```

### 2.2 Model Factory Pattern

**Purpose**: Automatically instantiate correct InferenceEngine based on architecture

```swift
// ModelFactory.swift - New file
actor ModelFactory {
    enum EngineType {
        case llama      // Llama, Llama2, Llama3
        case qwen       // Qwen, Qwen2
        case phi        // Phi, Phi2, Phi3
        case gemma      // Gemma
        case mistral    // Mistral
        case gpt        // GPT architectures
    }

    /// Determine engine type from metadata
    static func engineType(for metadata: GGUFMetadata) -> EngineType {
        let arch = metadata.architecture.lowercased()

        if arch.contains("llama") { return .llama }
        if arch.contains("qwen") { return .qwen }
        if arch.contains("phi") { return .phi }
        if arch.contains("gemma") { return .gemma }
        if arch.contains("mistral") { return .mistral }
        if arch.contains("gpt") { return .gpt }

        // Default fallback
        return .llama
    }

    /// Create appropriate inference engine
    static func createEngine(
        modelPath: String,
        metadata: GGUFMetadata,
        runtimeParams: RuntimeParams
    ) async throws -> any InferenceEngine {
        let engineType = engineType(for: metadata)

        switch engineType {
        case .llama, .qwen, .phi, .gemma, .mistral, .gpt:
            // All currently use LlamaInferenceEngine (llama.cpp supports all)
            return try await LlamaInferenceEngine(
                modelPath: modelPath,
                metadata: metadata,
                runtimeParams: runtimeParams
            )
        }
    }
}
```

### 2.3 Auto-Discovery Enhancement

**Current**: `scanForModels()` scans predefined directories
**Enhancement**: Add symlink support for the three new models

```swift
// ModelRegistry.swift - Enhanced scanning
extension ModelRegistry {
    /// Get model search paths (including symlink resolution)
    private func getModelSearchPaths() -> [String] {
        var paths: [String] = []

        // Bundle resources
        if let resourcePath = Bundle.main.resourcePath {
            paths.append(contentsOf: [
                "\(resourcePath)/Models",
                "\(resourcePath)/Resources/Models",
                resourcePath
            ])
        }

        return paths
    }

    /// Register new models with symlink support
    func registerNewModels() async {
        let newModels = [
            "Llama-3.3-70B-Instruct-Q4_1.gguf",
            "gpt-oss-20b-UD-Q4_K_XL.gguf",
            "Jan-v1-4B-Q4_K_M.gguf"
        ]

        for modelFile in newModels {
            for searchPath in getModelSearchPaths() {
                let fullPath = "\(searchPath)/\(modelFile)"

                // Check if file exists (supports symlinks)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory) {
                    if !isDirectory.boolValue {
                        await registerGGUFFile(at: fullPath)
                    }
                }
            }
        }
    }
}
```

### 2.4 Streaming Token Output

**Enhancement**: Add proper streaming support with AsyncStream

```swift
// InferenceEngine.swift - Add streaming protocol method
extension InferenceEngine {
    /// Stream tokens as they are generated
    func generateStream(prompt: String, maxTokens: Int32) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await prepare(prompt: prompt)

                    var tokenCount: Int32 = 0
                    while await !isDone && tokenCount < maxTokens {
                        if let token = try await generateNextToken() {
                            continuation.yield(token)
                            tokenCount += 1
                        } else {
                            break
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

---

## Phase 3: Error Recovery & Validation 🛡️

### 3.1 Model Load Failure Handling

```swift
// ModelManager.swift - Enhanced error recovery
extension ModelManager {
    func loadModelWithFallback(id: String) async throws {
        do {
            try await loadModel(id: id)
        } catch InferenceError.outOfMemory {
            // Retry with reduced parameters
            SystemLog().logEvent(event: "[ModelManager] OOM detected, retrying with reduced params")

            if let spec = await registry.getModelSpec(id: id) {
                var reducedParams = spec.runtimeParams
                reducedParams.nCtx = reducedParams.nCtx / 2
                reducedParams.nBatch = reducedParams.nBatch / 2
                reducedParams.nGpuLayers = 0

                await registry.updateRuntimeParams(for: id, params: reducedParams)
                try await loadModel(id: id)
            }
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            throw error
        }
    }
}
```

### 3.2 Unsupported Format Detection

```swift
// GGUFReader.swift - Validation
extension GGUFReader {
    static func isValidGGUFFile(at filePath: String) -> Bool {
        guard FileManager.default.fileExists(atPath: filePath) else {
            return false
        }

        do {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
            defer { try? handle.close() }

            guard let magicData = try? handle.read(upToCount: 4),
                  magicData.count == 4 else {
                return false
            }

            let magic = magicData.withUnsafeBytes { $0.load(as: UInt32.self) }
            return magic == 0x46554747 // "GGUF"
        } catch {
            return false
        }
    }
}
```

---

## Phase 4: Testing & Validation 🧪

### 4.1 Model Compatibility Tests

```swift
// ModelRegistryTests.swift
class ModelCompatibilityTests: XCTestCase {
    func testAllModelsCanBeDiscovered() async throws {
        let registry = ModelRegistry.shared
        await registry.scanForModels()

        let availableModels = await registry.getAvailableModelSpecs()
        XCTAssertGreaterThan(availableModels.count, 0, "No models discovered")

        // Verify new models are found
        let expectedModels = ["Llama-3.3-70B-Instruct", "gpt-oss-20b", "Jan-v1-4B"]
        for expected in expectedModels {
            XCTAssertTrue(
                availableModels.contains { $0.name.contains(expected) },
                "Model \(expected) not found"
            )
        }
    }

    func testGGUFMetadataExtraction() async throws {
        let searchPaths = [
            Bundle.main.resourcePath! + "/Models",
            Bundle.main.resourcePath! + "/Resources/Models"
        ]

        for path in searchPaths {
            let contents = try? FileManager.default.contentsOfDirectory(atPath: path)
            let ggufFiles = contents?.filter { $0.hasSuffix(".gguf") } ?? []

            for file in ggufFiles {
                let fullPath = "\(path)/\(file)"
                let metadata = try await GGUFReader.readMetadata(from: fullPath)

                XCTAssertFalse(metadata.architecture.isEmpty)
                XCTAssertGreaterThan(metadata.parameterCount, 0)
                XCTAssertGreaterThan(metadata.contextLength, 0)
            }
        }
    }

    func testModelLoadingRecovery() async throws {
        let manager = ModelManager.shared

        // Attempt to load each model
        for spec in await ModelRegistry.shared.getAvailableModelSpecs() {
            do {
                try await manager.loadModelWithFallback(id: spec.id)
                SystemLog().logEvent(event: "[Test] Successfully loaded: \(spec.name)")
            } catch {
                XCTFail("Failed to load model \(spec.name): \(error)")
            }
        }
    }
}
```

### 4.2 Static Analysis Guards

```swift
// Add to build script phase
#!/bin/bash
# Static analysis: Check for accidental llama.cpp binding imports

echo "🔍 Checking for unused llama.cpp bindings..."

FORBIDDEN_IMPORTS=(
    "import llama.swiftui"
    "from llama.cpp.bak"
)

for import in "${FORBIDDEN_IMPORTS[@]}"; do
    if grep -r "$import" NoesisNoema/Shared NoesisNoema/ModelRegistry; then
        echo "❌ ERROR: Found forbidden import: $import"
        exit 1
    fi
done

echo "✅ No forbidden imports found"
```

---

## Phase 5: Documentation Updates 📚

### 5.1 Architecture Documentation

```markdown
# NoesisNoema Model Architecture

## Overview
NoesisNoema uses a custom Swift wrapper layer around llama.cpp's C API.
The original llama.cpp Swift bindings are NOT used.

## Layer Structure

```
┌─────────────────────────────────────┐
│   ContentView / UI Layer            │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│   ModelManager (Model Selection)    │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│   ModelRegistry (Auto-Discovery)    │
│   - GGUFReader                       │
│   - AutotuneService                  │
│   - HardwareProfile                  │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│   InferenceEngine Protocol           │
│   (Architecture-agnostic interface)  │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│   LlamaInferenceEngine (Actor)       │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│   LlamaContext (Actor)               │
│   - Batch management                 │
│   - Sampling configuration           │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│   LibLlama (C API Shim)              │
│   - llama_batch_add                  │
│   - llama_decode                     │
│   - llama_sampler_*                  │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│   llama.xcframework                  │
│   (llama_macos / llama_ios)          │
└──────────────────────────────────────┘
```

## Adding New Models

1. Place GGUF file in `Resources/Models/`
2. Model is auto-discovered on next app launch
3. Metadata is extracted automatically
4. Runtime parameters are auto-tuned based on hardware

No code changes required! ✨
```

---

## Summary

### ✅ What's Already Working

1. **Custom Swift wrapper layer** - Complete and functional
2. **ModelRegistry** - Auto-discovery and registration
3. **GGUFReader** - Metadata extraction (heuristic-based)
4. **AutotuneService** - SHA256-cached optimization
5. **Protocol-based architecture** - InferenceEngine abstraction

### 🔧 Recommended Enhancements

1. **Phase 1**: Remove dead code (`externals/llama.cpp.bak`)
2. **Phase 2**: Add true GGUF binary header parsing
3. **Phase 3**: Enhance error recovery (OOM, unsupported formats)
4. **Phase 4**: Add comprehensive tests
5. **Phase 5**: Update documentation

### 🎯 Priority Actions

**High Priority:**
- ✅ Remove `externals/llama.cpp.bak` directory
- ✅ Clean Xcode build settings
- ✅ Add model compatibility tests

**Medium Priority:**
- 🔧 Enhance GGUFReader with binary parsing
- 🔧 Add streaming token output
- 🔧 Improve error messages

**Low Priority:**
- 📚 Add inline code documentation
- 📚 Create developer guide

---

**Status**: Ready for implementation
**Risk Level**: Low (architecture is sound, changes are additive)
**Estimated Effort**: 2-3 days
