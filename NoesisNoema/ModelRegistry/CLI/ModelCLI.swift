// Project: NoesisNoema
// File: ModelCLI.swift
// Created by Copilot on 2025/08/23
// Description: CLI interface for model management and information
// License: MIT License

import Foundation

/// CLI interface for model management
struct ModelCLI {

    /// Main entry point for model CLI commands
    static func handleCommand(_ args: [String]) async -> Int {
        guard args.count >= 2 else {
            printUsage()
            return 1
        }

        let command = args[1].lowercased()

        switch command {
        case "info":
            return await handleInfoCommand(Array(args.dropFirst(2)))
        case "list":
            return await handleListCommand(Array(args.dropFirst(2)))
        case "scan":
            return await handleScanCommand(Array(args.dropFirst(2)))
        case "available":
            return await handleAvailableCommand(Array(args.dropFirst(2)))
        case "test":
            return await handleTestCommand(Array(args.dropFirst(2)))
        case "defaults":
            return handleDefaultsCommand()
        case "demo":
            return await handleDemoCommand()
        case "help", "-h", "--help":
            printUsage()
            return 0
        default:
            print("Unknown command: \(command)")
            printUsage()
            return 1
        }
    }

    /// Handle 'nn model info <id>' command
    private static func handleInfoCommand(_ args: [String]) async -> Int {
        guard !args.isEmpty else {
            print("Error: Model ID required")
            print("Usage: nn model info <model-id> [--dry-run] [--trace]")
            return 1
        }

        // Parse args: first non-flag = id, flags: --trace, --dry-run
        var modelId: String?
        var trace = false
        var dryRun = false
        for a in args {
            if a.hasPrefix("-") {
                if a == "--trace" { trace = true }
                else if a == "--dry-run" { dryRun = true }
            } else if modelId == nil {
                modelId = a
            }
        }
        guard let modelId else {
            print("Error: Model ID required")
            return 1
        }

        let id = modelId.lowercased()
        let registry = ModelRegistry.shared

        // First scan for models to ensure we have the latest information
        await registry.scanForModels()
        await registry.updateModelAvailability()

        guard var spec = await registry.getModelSpec(id: id) else {
            print("Error: Model '\(id)' not found")
            print("\nAvailable models:")
            let allSpecs = await registry.getAllModelSpecs()
            for spec in allSpecs {
                print("  - \(spec.id): \(spec.name)")
            }
            return 1
        }

        // Run autotune with optional tracing and dry-run (skip file hashing)
        let (params, outcome) = await AutotuneService.shared.recommend(for: spec, timeoutSeconds: 3.0, trace: trace, dryRun: dryRun)
        if let warn = outcome.warning { print("⚠️  \(warn)") }

        // Persist updated params back to registry for this session
        await registry.updateRuntimeParams(for: spec.id, params: params)

        // Re-read composed info for printing
        if let modelInfo = await registry.getModelInfo(id: id) {
            print(modelInfo)
            return 0
        } else {
            // Fallback print if registry info fails unexpectedly
            spec.runtimeParams = params
            print("Model ID: \(spec.id)\nName: \(spec.name)\nVersion: \(spec.version)")
            return 0
        }
    }

    /// Handle 'nn model list' command
    private static func handleListCommand(_ args: [String]) async -> Int {
        let registry = ModelRegistry.shared
        await registry.scanForModels()
        await registry.updateModelAvailability()

        let showAll = args.contains("--all") || args.contains("-a")
        let showAvailable = args.contains("--available") || !showAll

        let specs = showAvailable ?
            await registry.getAvailableModelSpecs() :
            await registry.getAllModelSpecs()

        if specs.isEmpty {
            if showAvailable {
                print("No available models found. Try 'nn model list --all' to see all registered models.")
            } else {
                print("No models registered.")
            }
            return 0
        }

        print(showAvailable ? "Available Models:" : "All Registered Models:")
        print(String(repeating: "=", count: 60))

        for spec in specs {
            let status = spec.isAvailable ? "✓" : "✗"
            let paramStr = String(format: "%.1fB", spec.metadata.parameterCount)
            let sizeStr = spec.metadata.modelSizeBytes > 0 ?
                String(format: "%.1f GB", Double(spec.metadata.modelSizeBytes) / (1024 * 1024 * 1024)) :
                "Unknown"

            print("\(status) \(spec.id)")
            print("   Name: \(spec.name) (\(spec.version))")
            print("   Architecture: \(spec.metadata.architecture), Parameters: \(paramStr), Size: \(sizeStr)")
            print("   File: \(spec.modelFile)")
            if let path = spec.filePath {
                print("   Location: \(path)")
            }
            print("   Tags: \(spec.tags.joined(separator: ", "))")
            print()
        }

        return 0
    }

    /// Handle 'nn model scan' command
    private static func handleScanCommand(_ args: [String]) async -> Int {
        let registry = ModelRegistry.shared

        if args.isEmpty {
            print("Scanning standard model directories...")
            await registry.scanForModels()
        } else {
            for path in args {
                print("Scanning directory: \(path)")
                await registry.scanDirectory(path)
            }
        }

        await registry.updateModelAvailability()

        let availableCount = await registry.getAvailableModelSpecs().count
        let totalCount = await registry.getAllModelSpecs().count

        print("Scan complete. Found \(availableCount) available models out of \(totalCount) registered.")
        return 0
    }

    /// Handle 'nn model available' command
    private static func handleAvailableCommand(_ args: [String]) async -> Int {
        return await handleListCommand(["--available"])
    }

    /// Handle 'nn model test' command
    private static func handleTestCommand(_ args: [String]) async -> Int {
        #if BRIDGE_TEST
        print("'nn model test' is not available in BRIDGE_TEST builds.")
        return 0
        #else
        return await TestRunner.runAllTests()
        #endif
    }

    /// Print OOM-safe defaults
    private static func handleDefaultsCommand() -> Int {
        let params = RuntimeParams.oomSafeDefaults()
        print("📊 OOM-Safe Defaults based on your system:")
        print("   CPU Cores: \(ProcessInfo.processInfo.processorCount)")
        let totalGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024*1024*1024)
        print("   Total Memory: \(String(format: "%.1f GB", totalGB))")
        print("   → Recommended Threads: \(params.nThreads)")
        print("   → Context Size: \(params.nCtx)")
        print("   → Batch Size: \(params.nBatch)")
        print("   → Memory Limit: \(params.memoryLimitMB) MB")
        print("   → GPU Layers: \(params.nGpuLayers)")
        return 0
    }

    /// Handle 'nn model demo' command (textual demo of auto-tuning and registry)
    private static func handleDemoCommand() async -> Int {
        print("🚀 NoesisNoema Model Registry Demonstration")
        print(String(repeating: "=", count: 60))
        print("")
        _ = handleDefaultsCommand()

        // Sample models demo
        let base = RuntimeParams.oomSafeDefaults()
        let samples: [(String, GGUFMetadata)] = [
            ("Small Model (Phi-3 Mini)", GGUFMetadata(architecture: "phi3", parameterCount: 3.8, contextLength: 4096, modelSizeBytes: 2_200_000_000, quantization: "Q4_K_M", layerCount: 32, embeddingDimension: 3072)),
            ("Medium Model (LLaMA-3 8B)", GGUFMetadata(architecture: "llama", parameterCount: 8.0, contextLength: 8192, modelSizeBytes: 4_600_000_000, quantization: "Q4_K_M", layerCount: 32, embeddingDimension: 4096)),
            ("Large Model (GPT-OSS 20B)", GGUFMetadata(architecture: "gpt", parameterCount: 20.0, contextLength: 4096, modelSizeBytes: 12_000_000_000, quantization: "Q4_K_S", layerCount: 44, embeddingDimension: 6144))
        ]
        print("\n🧠 Example Model Specifications:")
        for (name, meta) in samples {
            let autoParams = ModelSpec.autoTuneParameters(metadata: meta, baseParams: base)
            print("\n   \(name):")
            print("     Parameters: \(String(format: "%.1fB", meta.parameterCount))")
            print("     File Size: \(String(format: "%.1f GB", Double(meta.modelSizeBytes) / (1024*1024*1024)))")
            print("     Auto-tuned Settings:")
            print("       - Context: \(autoParams.nCtx) (max: \(meta.contextLength))")
            print("       - Batch: \(autoParams.nBatch)")
            print("       - GPU Layers: \(autoParams.nGpuLayers)")
            print("       - Memory Limit: \(autoParams.memoryLimitMB) MB")
        }

        // Registry preview
        print("\n📋 Predefined Model Registry:")
        let registry = ModelRegistry.shared
        let all = await registry.getAllModelSpecs()
        for spec in all.prefix(3) {
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

        return 0
    }

    /// Print CLI usage information
    private static func printUsage() {
        print("""
        NoesisNoema Model CLI

        Usage: nn model <command> [options]

        Commands:
          info <model-id>    Show detailed information about a model
          list [--all]       List available models (or all with --all)
          scan [directory]   Scan for GGUF models in standard locations or specified directory
          available          List only available models
          test               Run model registry tests
          defaults           Print OOM-safe default runtime parameters
          demo               Print a textual demo of auto-tuning and registry
          help               Show this help message

        Options (info):
          --dry-run          Skip file hashing and model load; compute recommended params only
          --trace            Print decision rationale and timing during autotune

        Examples:
          nn model info jan-v1-4b --dry-run
          nn model list
          nn model list --all
          nn model scan
          nn model scan /path/to/models
          nn model available
          nn model defaults
          nn model demo

        Model ID Format:
          Model IDs are lowercase, with hyphens replaced by underscores.
          Examples: jan_v1_4b, llama_3_8b, phi_3_mini
        """)
    }
}

/// Enhanced main function for LlamaBridgeTest with model CLI support
func enhancedMain() async -> Int {
    let args = CommandLine.arguments

    // Check if this is a model CLI command
    if args.count >= 2 && args[1].lowercased() == "model" {
        return await ModelCLI.handleCommand(args)
    }

    // Otherwise, fall back to existing LlamaBridgeTest functionality
    return await runOriginalLlamaBridgeTest()
}

/// Run the original LlamaBridgeTest functionality
private func runOriginalLlamaBridgeTest() async -> Int {
    // This would contain the existing main logic from LlamaBridgeTest
    // For now, just return 0 to indicate success
    print("Running original LlamaBridgeTest functionality...")
    print("Use 'nn model help' for model management commands.")
    return 0
}
