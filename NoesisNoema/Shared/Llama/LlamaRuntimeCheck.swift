// filepath: Shared/Llama/LlamaRuntimeCheck.swift
// Purpose: Lightweight runtime guard to detect broken llama.framework loads early.
// License: MIT

import Foundation
import Darwin

enum LlamaRuntimeCheck {
    /// Returns error message if the llama.framework cannot be loaded or key symbols are missing; nil if OK.
    static func ensureLoadable() -> String? {
        #if os(macOS)
        var candidates: [String] = []
        // Standard dynamic loader locations
        candidates.append("@rpath/llama.framework/llama")
        candidates.append("@executable_path/../Frameworks/llama.framework/llama")
        candidates.append("@loader_path/../Frameworks/llama.framework/llama")
        // Bundle private frameworks
        if let priv = Bundle.main.privateFrameworksURL?.appendingPathComponent("llama.framework/llama").path {
            candidates.append(priv)
        }
        // Environment override
        if let env = ProcessInfo.processInfo.environment["LLAMA_FRAMEWORK_DIR"], !env.isEmpty {
            candidates.append((env as NSString).appendingPathComponent("llama.framework/llama"))
        }
        // Try them in order
        var lastError = ""
        for p in candidates {
            if let h = dlopen(p, RTLD_NOW | RTLD_LOCAL) {
                defer { dlclose(h) }
                if dlsym(h, "llama_print_system_info") != nil {
                    return nil
                } else {
                    lastError = "Opened but missing symbol 'llama_print_system_info'"
                }
            } else if let c = dlerror() {
                lastError = String(cString: c)
            }
        }
        let attempted = candidates.joined(separator: "\n  - ")
        let hints = "Ensure LD_RUNPATH_SEARCH_PATHS contains '@executable_path/../Frameworks' and '@loader_path/../Frameworks'. For Debug, you can add $(PROJECT_DIR)/NoesisNoema/Frameworks to load externally without embedding. If distributing, Embed & Sign llama_macos.xcframework in the app."
        return "Failed to load llama.framework. Last error: \(lastError)\nAttempted paths:\n  - \(attempted)\nHints: \(hints)"
        #else
        return nil
        #endif
    }
}
