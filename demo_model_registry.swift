#!/usr/bin/env swift
import Foundation

// Wrapper that invokes the compiled Model CLI demo instead of importing app types.

func candidateBinaries() -> [String] {
    var paths: [String] = []
    let fm = FileManager.default
    let cwd = fm.currentDirectoryPath
    paths.append("\(cwd)/build/Debug/LlamaBridgeTest")
    paths.append("\(cwd)/build/Build/Products/Debug/LlamaBridgeTest")
    if let env = ProcessInfo.processInfo.environment["NOESIS_LLAMA_BRIDGE_BIN"], !env.isEmpty { paths.insert(env, at: 0) }
    return paths
}

func findBinary() -> String? {
    let fm = FileManager.default
    for p in candidateBinaries() { if fm.isExecutableFile(atPath: p) { return p } }
    return nil
}

func run(_ exe: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    p.standardOutput = FileHandle.standardOutput
    p.standardError = FileHandle.standardError
    do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { fputs("Failed to launch: \(error)\n", stderr); return 2 }
}

if let bin = findBinary() {
    print("🚀 Running Model Registry Demo via CLI → \(bin) model demo\n")
    let code = run(bin, ["model", "demo"])
    exit(code)
} else {
    fputs("error: LlamaBridgeTest binary not found.\n", stderr)
    fputs("Hint: Build the CLI first, then re-run this script.\n", stderr)
    fputs("   xcodebuild -scheme LlamaBridgeTest -configuration Debug build\n", stderr)
    fputs("   ./demo_model_registry.swift\n", stderr)
    exit(2)
}
