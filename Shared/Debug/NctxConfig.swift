//
//  NctxConfig.swift
//  NoesisNoema
//
//  DEBUG-only override for the on-device generator context window (n_ctx).
//
//  Purpose: lets the n_ctx footprint+latency harness sweep the generator's
//  KV-cache size across {1024, 2048, 4096, 8192} WITHOUT recompiling. The
//  device generator builds a fresh `LlamaContext` per question
//  (see `runNoesisCompletion`), so the KV cache is re-allocated on the next
//  generation as soon as this value changes — no persistent generator to
//  unload manually.
//
//  Guardrails:
//  - This knob ONLY exists in DEBUG. In Release the device n_ctx is the
//    unchanged literal default (1024). Shipping behaviour is untouched.
//  - Pure value/UserDefaults transformation. No model logic, no retrieval
//    change. Measurement scaffolding only.
//
//  License: MIT License
//

import Foundation

/// DEBUG-switchable device generator n_ctx for the measurement harness.
enum NctxConfig {

    /// The four levels the harness measures. Picker is constrained to these.
    static let allowedValues: [Int32] = [1024, 2048, 4096, 8192]

    /// Shipping default for the on-device generator (matches the historical
    /// `LibLlama.create_context` iOS value). Returned verbatim in Release.
    static let deviceDefault: Int32 = 1024

    /// UserDefaults key backing the DEBUG override.
    static let defaultsKey = "debug.nctx.deviceOverride"

    /// Effective device n_ctx used by `LibLlama.create_context` on iOS.
    ///
    /// DEBUG: reads the harness picker's UserDefaults override, falling back to
    /// `deviceDefault` when unset/invalid. Release: always `deviceDefault`.
    static var deviceNCtx: Int32 {
        #if DEBUG
        let stored = Int32(UserDefaults.standard.integer(forKey: defaultsKey))
        return allowedValues.contains(stored) ? stored : deviceDefault
        #else
        return deviceDefault
        #endif
    }

    #if DEBUG
    /// Persist a new device n_ctx selection (no-op for out-of-range values).
    /// The next generation's fresh `LlamaContext` allocates the new KV cache.
    static func setDeviceNCtx(_ value: Int32) {
        guard allowedValues.contains(value) else { return }
        UserDefaults.standard.set(Int(value), forKey: defaultsKey)
        SystemLog().logEvent(event: "[NctxConfig] device n_ctx override set to \(value); takes effect on next generator load")
    }
    #endif
}
