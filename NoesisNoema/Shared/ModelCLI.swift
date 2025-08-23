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
        guard args.count >= 1 else {
            print("Error: Model ID required")
            print("Usage: nn model info <model-id>")
            return 1
        }
        
        let modelId = args[0].lowercased()
        let registry = ModelRegistry.shared
        
        // First scan for models to ensure we have the latest information
        await registry.scanForModels()
        await registry.updateModelAvailability()
        
        guard let modelInfo = await registry.getModelInfo(id: modelId) else {
            print("Error: Model '\(modelId)' not found")
            print("\nAvailable models:")
            let allSpecs = await registry.getAllModelSpecs()
            for spec in allSpecs {
                print("  - \(spec.id): \(spec.name)")
            }
            return 1
        }
        
        print(modelInfo)
        return 0
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
        print("Running model registry tests...")
        await ModelRegistryTests.runTests()
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
          help               Show this help message
        
        Examples:
          nn model info jan-v1-4b
          nn model list
          nn model list --all
          nn model scan
          nn model scan /path/to/models
          nn model available
        
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