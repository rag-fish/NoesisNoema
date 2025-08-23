# ModelRegistry Implementation Summary

## Overview

This implementation adds a comprehensive model registry system to NoesisNoema with automatic parameter tuning based on GGUF file metadata and OOM-safe defaults.

## Core Components

### 1. ModelSpec.swift
- **RuntimeParams**: Runtime parameters with OOM-safe defaults based on system capabilities
- **GGUFMetadata**: Structure for GGUF file metadata (architecture, parameters, context length, etc.)
- **ModelSpec**: Complete model specification with auto-tuned parameters

Key features:
- Device-specific defaults (iOS vs macOS)
- Memory-aware parameter tuning
- Automatic context and batch size optimization
- Support for flash attention detection

### 2. GGUFReader.swift
- Reads GGUF file metadata without loading tensor data
- Extracts model architecture, parameter count, quantization type
- Estimates parameter count from model dimensions
- Validates GGUF file format

### 3. ModelRegistry.swift
- Central registry for managing model specifications
- Automatic scanning of standard model directories
- Model availability tracking
- Search by ID, name, tag, or architecture
- Predefined specifications for common models

### 4. ModelCLI.swift
- CLI interface for model management
- Commands: `info`, `list`, `scan`, `available`, `test`
- Detailed model information display
- Integration with existing LlamaBridgeTest

### 5. Updated ModelManager.swift
- Uses ModelRegistry instead of hardcoded mappings
- Async model switching with auto-tuned parameters
- Backward compatibility with existing model names
- Runtime parameter access for UI

## OOM-Safe Defaults

The system provides memory-safe defaults that prevent out-of-memory crashes:

### iOS Devices
- **8GB+ RAM**: ctx=4096, batch=512, memory_limit=2GB, gpu_layers=999
- **6GB RAM**: ctx=2048, batch=256, memory_limit=1.5GB, gpu_layers=64  
- **<6GB RAM**: ctx=1024, batch=128, memory_limit=1GB, gpu_layers=32

### macOS Devices
- **16GB+ RAM**: ctx=8192, batch=1024, memory_limit=4GB, gpu_layers=999
- **8GB RAM**: ctx=4096, batch=512, memory_limit=2GB, gpu_layers=80
- **<8GB RAM**: ctx=2048, batch=256, memory_limit=1GB, gpu_layers=40

## Auto-Tuning Logic

Parameters are automatically adjusted based on:

1. **Model Size**: Large models (>20B params) get reduced batch sizes and conservative GPU offloading
2. **Quantization**: Higher quality quantization (Q8, Q6) reduces batch size to fit in memory
3. **Context Length**: Model's maximum context length limits the context window
4. **Flash Attention**: Enabled when supported by architecture
5. **Memory Safety**: Memory limits set to 2x model size with safety margins

## CLI Interface

```bash
# Show detailed model information
nn model info jan-v1-4b

# List available models
nn model list
nn model list --all

# Scan for GGUF files
nn model scan
nn model scan /path/to/models

# Run functionality tests
nn model test
```

## Example Model Information

```
Model ID: jan-v1-4b
Name: Jan-V1-4B
Version: 4B
Status: ✓ Available
File: Jan-v1-4B-Q4_K_M.gguf

Architecture: qwen
Parameters: 4.0B
Quantization: Q4_K_M
Context Length: 32768
Layers: 32
Flash Attention: Yes

Runtime Parameters:
- Threads: 6
- GPU Layers: 999
- Context Size: 4096
- Batch Size: 512
- Memory Limit: 2048 MB
- Temperature: 0.7

Tags: qwen, small, q4_k_m, long-context
```

## Integration

The new system integrates seamlessly with existing code:

1. **ModelManager** continues to work with existing UI code
2. **LlamaBridgeTest** gains new CLI commands while maintaining compatibility
3. **Backward compatibility** with existing model names and switching logic
4. **Async operations** for better performance with file scanning

## Benefits

1. **Automatic Optimization**: No manual parameter tuning required
2. **Memory Safety**: Prevents OOM crashes with conservative defaults
3. **Device Awareness**: Optimizes for iOS vs macOS capabilities
4. **Model Discovery**: Automatically finds and registers GGUF files
5. **Centralized Management**: Single source of truth for model specifications
6. **CLI Interface**: Easy model information access and debugging
7. **Extensibility**: Easy to add new models and architectures

## Testing

Comprehensive test suite included:
- OOM-safe defaults validation
- Model spec auto-tuning verification
- GGUF reader functionality
- Model registry operations
- CLI information formatting
- Runtime parameter optimization

Run tests with: `nn model test`

This implementation fulfills the requirements for "ModelSpec/RuntimeParams + GGUF autotune" with OOM-safe defaults and provides a solid foundation for advanced model management in NoesisNoema.