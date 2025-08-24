// filepath: Shared/LlamaRuntimeCheck.swift
// Purpose: Lightweight runtime guard to detect broken llama.framework loads early.
// License: MIT

import Foundation
import Darwin

enum LlamaRuntimeCheck {
    /// Returns error message if the llama.framework cannot be loaded or key symbols are missing; nil if OK.
    static func ensureLoadable() -> String? {
        // Try to open via rpath (app bundle should embed llama.framework)
        let path = "@" + "rpath/llama.framework/llama"
        guard dlopen(path, RTLD_NOW) != nil else {
            return "Failed to load llama.framework (check rpath/embed)."
        }
        // Check a representative symbol is resolvable
        if dlsym(UnsafeMutableRawPointer(bitPattern: -2), "llama_print_system_info") == nil {
            return "Missing symbol: llama_print_system_info"
        }
        return nil
    }
}
