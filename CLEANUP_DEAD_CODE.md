# Dead Code Cleanup Plan

## Status: Ready for Removal

### 1. Unused llama.cpp Swift Bindings

**Location**: `NoesisNoema/externals/llama.cpp.bak/`

**Contents**:
- `examples/llama.swiftui/llama.swiftui/llama_swiftuiApp.swift`
- `examples/llama.swiftui/llama.cpp.swift/LibLlama.swift`
- `examples/llama.swiftui/llama.swiftui/Models/LlamaState.swift`

**Status**: ❌ **DEAD CODE** - Not referenced anywhere in active codebase

**Action**: Safe to delete entire directory

```bash
rm -rf NoesisNoema/externals/llama.cpp.bak
```

### 2. Old Build Path References in Xcode Project

**Location**: `NoesisNoema.xcodeproj/project.pbxproj`

**References**: 20+ references to old build paths in framework search paths:
- `$(PROJECT_DIR)/NoesisNoema/externals/llama.cpp/build-ios-sim/...`
- `$(PROJECT_DIR)/NoesisNoema/externals/llama.cpp.bak/build-ios-sim/...`

**Status**: ⚠️ **Obsolete** - Leftover from previous build configurations

**Action**: Clean framework search paths in Xcode Build Settings

### 3. Verification

After cleanup, verify:
- ✅ Project builds successfully
- ✅ No import errors
- ✅ Custom wrapper layer (`LibLlama.swift`, `LlamaState.swift`) still functions
- ✅ Model loading works from `Resources/Models/`

## Current Custom Swift Wrapper (✅ Active)

The project uses a **fully custom Swift wrapper layer**:

1. **LibLlama.swift** - Thin C API shim layer
2. **LlamaContext** actor - Actor-isolated context management
3. **LlamaState** - High-level model state management (@MainActor)
4. **LlamaInferenceEngine** - Protocol-based inference engine
5. **InferenceEngine** protocol - Generic interface for all GGUF models

## ModelRegistry Architecture (✅ Active & Modern)

Already implements dynamic model discovery and auto-tuning:

- **GGUFReader**: Reads metadata from any GGUF file
- **ModelRegistry**: Auto-discovers models in `Resources/Models/`
- **AutotuneService**: SHA256-cached parameter optimization
- **HardwareProfile**: Runtime hardware detection

## Recommendation

✅ **Proceed with cleanup** - No risk to active codebase
