#!/usr/bin/env swift
import Foundation

// Wrapper: run LlamaBridgeTest with --defaults to verify basic wiring without importing app types.

func candidateBinaries() -> [String] {
    var paths: [String] = []
    let fm = FileManager.default
    let cwd = fm.currentDirectoryPath
    // Project-local (rare)
    paths.append("\(cwd)/build/Debug/LlamaBridgeTest")
    paths.append("\(cwd)/build/Build/Products/Debug/LlamaBridgeTest")
    // DerivedData scan
    if let home = ProcessInfo.processInfo.environment["HOME"] {
        let dd = "\(home)/Library/Developer/Xcode/DerivedData"
        if let entries = try? fm.contentsOfDirectory(atPath: dd) {
            // Prefer newest NoesisNoema-* entry
            let candidates = entries.filter { $0.hasPrefix("NoesisNoema-") }.sorted { a, b in
                let pa = "\(dd)/\(a)"; let pb = "\(dd)/\(b)"
                let ma = (try? fm.attributesOfItem(atPath: pa)[.modificationDate] as? Date) ?? .distantPast
                let mb = (try? fm.attributesOfItem(atPath: pb)[.modificationDate] as? Date) ?? .distantPast
                return ma > mb
            }
            for c in candidates {
                let p = "\(dd)/\(c)/Build/Products/Debug/LlamaBridgeTest"
                paths.append(p)
            }
        }
    }
    // Custom override via env
    if let envPath = ProcessInfo.processInfo.environment["NOESIS_LLAMA_BRIDGE_BIN"], !envPath.isEmpty {
        paths.insert(envPath, at: 0)
    }
    return paths
}

func findBinary() -> String? {
    let fm = FileManager.default
    for p in candidateBinaries() { if fm.isExecutableFile(atPath: p) { return p } }
    return nil
}

func run(_ launchPath: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = args
    p.standardInput = FileHandle.standardInput
    p.standardOutput = FileHandle.standardOutput
    p.standardError = FileHandle.standardError
    do {
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    } catch {
        fputs("Failed to launch: \(error)\n", stderr)
        return 2
    }
}

if let bin = findBinary() {
    print("🧪 Running LlamaBridgeTest --defaults (no app-type imports) → \(bin) --defaults\n")
    let code = run(bin, ["--defaults"])
    exit(code)
} else {
    fputs("error: LlamaBridgeTest binary not found.\n", stderr)
    fputs("Hint: Build the CLI first, then re-run this script.\n", stderr)
    fputs("   xcodebuild -scheme LlamaBridgeTest -configuration Debug build\n", stderr)
    fputs("   ./verify_implementation.swift\n", stderr)
    exit(2)
}
