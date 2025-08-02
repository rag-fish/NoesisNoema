//
//  main.swift
//  LlamaBridgeTest
//
//  Created by Раскольников on 2025/07/20.
//

//  Description: A test harness for the LlamaCpp interoperability layer.
//  License: MIT License

//
//  main.swift
//  NoesisNoema (Test Harness using LlamaState)
//
//  Description: Swift-native test for LlamaState wrapper
//

import Foundation
//import LlamaState // Adjust if actual class/module name differs (e.g. import NoesisNoema if that's where LlamaState lives)


let fm = FileManager.default
let cwd = fm.currentDirectoryPath
let fileName = "llama3-8b.gguf"

var checkedPaths: [String] = []

// 1. Check current directory
let pathCWD = "\(cwd)/\(fileName)"
checkedPaths.append(pathCWD)

// 2. Check same directory as executable
let exePath = CommandLine.arguments[0]
let exeDir = URL(fileURLWithPath: exePath).deletingLastPathComponent().path
let pathExeDir = "\(exeDir)/\(fileName)"
if pathExeDir != pathCWD { checkedPaths.append(pathExeDir) }

// 3. Check Bundle.main.resourceURL (rarely works for CLI, but included for completeness)
if let bundleResourceURL = Bundle.main.resourceURL {
    let pathBundle = bundleResourceURL.appendingPathComponent(fileName).path
    if pathBundle != pathCWD && pathBundle != pathExeDir { checkedPaths.append(pathBundle) }
}

// Print all attempted paths
print("Attempting to find '\(fileName)' at:")
for path in checkedPaths {
    print("  - \(path)")
    if fm.fileExists(atPath: path) {
        print("FOUND: \(path)")

        // === LlamaState integration ===
        Task {
            let llama = await LlamaState()
            do {
                try await llama.loadModel(modelUrl: URL(fileURLWithPath: path))
//                let prompt = "Who are you?"
//                let prompt = "<|user|>\nWho are you?\n<|assistant|>\n"
                let prompt = "Q: Summarize the contents of Spinoza's Ethic\nA:"
                let response: String = await llama.complete(text: prompt)
                print("Model completion: \(response)")
            } catch {
                print("Error running inference: \(error)")
            }
            exit(0)
        }
        dispatchMain() // Prevent CLI from exiting before Task finishes
    }
}
print("NOT FOUND in any attempted path!")
