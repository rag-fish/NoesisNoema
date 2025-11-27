// filepath: ModelRegistry/Autotune/AutotuneService.swift
// Project: NoesisNoema
// File: AutotuneService.swift
// Description: Asynchronous auto-tuning with caching, timeout, and tracing
// License: MIT License

import Foundation
import CryptoKit

/// Result metadata for an autotune operation
struct AutotuneOutcome: Sendable {
    let cacheHit: Bool
    let timedOut: Bool
    let usedFallback: Bool
    let warning: String?
}

/// Autotune service that computes recommended RuntimeParams for a model asynchronously.
/// Provides caching keyed by (fileSHA256 + quant + deviceId) and supports timeout and tracing.
actor AutotuneService {
    static let shared = AutotuneService()

    // In-memory cache
    private var cache: [String: RuntimeParams] = [:]

    /// Clear all cached recommendations (used when user requests re-tune)
    func clearCache() {
        cache.removeAll()
    }

    // Conservative fallback presets for unknown quantization or timeouts
    nonisolated private func conservativePreset(base: RuntimeParams, meta: GGUFMetadata) -> RuntimeParams {
        var p = base
        // Cap aggressively
        if meta.parameterCount >= 20.0 {
            p.nBatch = min(p.nBatch, 256)
            p.nGpuLayers = min(p.nGpuLayers, 10)
        } else if meta.parameterCount >= 7.0 {
            p.nBatch = min(p.nBatch, 384)
            p.nGpuLayers = min(p.nGpuLayers, 16)
        } else {
            p.nBatch = min(p.nBatch, 512)
            p.nGpuLayers = min(p.nGpuLayers, 20)
        }
        p.nCtx = min(p.nCtx, meta.contextLength)
        return p
    }

    /// Create a stable device id string from hardware profile
    nonisolated private func deviceId(from hw: HardwareProfile) -> String {
        let mem = String(format: "%.1f", hw.memTotalGB)
        let vram = String(format: "%.1f", hw.vramTotalGB)
        return "\(hw.arch)-mem\(mem)-vram\(vram)"
    }

    /// Compute SHA-256 for a file using streaming to avoid loading entire file into memory.
    nonisolated private func sha256Hex(ofFile path: String, chunkSize: Int = 2 * 1024 * 1024) throws -> String {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            return "nofile"
        }
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = try? handle.read(upToCount: chunkSize) ?? Data()
            if let d = data, !d.isEmpty { hasher.update(data: d); return true }
            return false
        }) {}
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // Actor-isolated cache accessors
    private func cachedParams(for key: String) -> RuntimeParams? { cache[key] }
    private func putCachedParams(_ params: RuntimeParams, for key: String) { cache[key] = params }

    /// Internal core implementation that can accept injected hash/device providers for tests
    private func recommendCore(spec: ModelSpec,
                               base: RuntimeParams,
                               timeoutSeconds: Double,
                               trace: Bool,
                               dryRun: Bool = false,
                               injectedHasher: (() async throws -> String)? = nil,
                               injectedDeviceId: (() -> String)? = nil) async -> (RuntimeParams, AutotuneOutcome) {
        // Trace helper
        func tlog(_ msg: String) { if trace { print("[autotune] " + msg) } }

        // Race autotune work against timeout (first finished wins)
        let deadlineNs = UInt64(max(0.1, timeoutSeconds) * 1_000_000_000)
        let result = await withTaskGroup(of: (RuntimeParams, AutotuneOutcome).self) { group -> (RuntimeParams, AutotuneOutcome) in
            // Main work task
            group.addTask { [weak self] in
                guard let self = self else {
                    let fb = self?.conservativePreset(base: base, meta: spec.metadata) ?? base
                    return (fb, AutotuneOutcome(cacheHit: false, timedOut: false, usedFallback: true, warning: "Autotune service deallocated"))
                }
                do {
                    tlog("probing hardware…")
                    let hw = HardwareProbe.probe()
                    let devId = injectedDeviceId?() ?? self.deviceId(from: hw)
                    tlog("device: arch=\(hw.arch), mem=\(hw.memTotalGB)GB, vram=\(hw.vramTotalGB)GB → id=\(devId)")

                    let quant = spec.metadata.quantization.uppercased()
                    tlog("quantization=\(quant)")

                    // Compute hash (or injected); dryRun skips file hashing
                    let sha: String
                    if let injectedHasher {
                        sha = try await injectedHasher()
                    } else if dryRun {
                        tlog("dry-run: skipping file hashing")
                        sha = "nofile"
                    } else if let path = spec.filePath {
                        tlog("hashing file: \(path)")
                        sha = try self.sha256Hex(ofFile: path)
                    } else {
                        tlog("no filePath; using 'nofile' marker")
                        sha = "nofile"
                    }
                    let cacheKey = "\(sha)|\(quant)|\(devId)"
                    tlog("cache key=\(cacheKey)")

                    // Cache lookup
                    if let cached = await self.cachedParams(for: cacheKey) {
                        tlog("cache hit; returning cached params")
                        return (cached, AutotuneOutcome(cacheHit: true, timedOut: false, usedFallback: false, warning: nil))
                    }

                    // Compute tuned params
                    tlog("computing tuned params from base…")
                    var tuned = ModelSpec.autoTuneParameters(metadata: spec.metadata, baseParams: base)

                    var usedFallback = false
                    var warn: String? = nil

                    // Unknown quantization fallback table
                    let knownPrefixes = ["Q2", "Q3", "Q4", "Q5", "Q6", "Q8"]
                    if !knownPrefixes.contains(where: { quant.hasPrefix($0) }) {
                        tlog("unknown quantization; applying conservative preset")
                        tuned = self.conservativePreset(base: base, meta: spec.metadata)
                        usedFallback = true
                        warn = "Unknown quantization (\(spec.metadata.quantization)); used conservative preset"
                    }

                    // Cap nCtx to model capability (safety)
                    if tuned.nCtx > spec.metadata.contextLength {
                        tlog("cap nCtx to model max \(spec.metadata.contextLength)")
                        tuned.nCtx = spec.metadata.contextLength
                    }

                    // Save to cache
                    await self.putCachedParams(tuned, for: cacheKey)
                    tlog("saved to cache")
                    return (tuned, AutotuneOutcome(cacheHit: false, timedOut: false, usedFallback: usedFallback, warning: warn))
                } catch {
                    tlog("error during autotune: \(error)")
                    // On error, fallback conservatively
                    let fb = self.conservativePreset(base: base, meta: spec.metadata)
                    return (fb, AutotuneOutcome(cacheHit: false, timedOut: false, usedFallback: true, warning: "Autotune error: \(error.localizedDescription)"))
                }
            }

            // Timeout task
            group.addTask {
                try? await Task.sleep(nanoseconds: deadlineNs)
                let fb = self.conservativePreset(base: base, meta: spec.metadata)
                let warn = "Autotune timed out after \(Int(timeoutSeconds * 1000))ms; used conservative preset"
                if trace { print("[autotune] timeout reached; returning fallback") }
                return (fb, AutotuneOutcome(cacheHit: false, timedOut: true, usedFallback: true, warning: warn))
            }

            // Wait for the first finished task
            if let first = await group.next() {
                group.cancelAll()
                return first
            }
            // Should not reach; fallback
            let fb = self.conservativePreset(base: base, meta: spec.metadata)
            return (fb, AutotuneOutcome(cacheHit: false, timedOut: true, usedFallback: true, warning: "Autotune race ended without result"))
        }
        return result
    }

    /// Public API: Recommend runtime params with timeout and optional tracing.
    /// - Parameters:
    ///   - spec: Model specification to tune for.
    ///   - timeoutSeconds: Max seconds before returning fallback (default 3.0).
    ///   - trace: When true, prints step-by-step logs.
    ///   - dryRun: When true, skip any file I/O (hashing) for faster CI.
    func recommend(for spec: ModelSpec, timeoutSeconds: Double = 3.0, trace: Bool = false, dryRun: Bool = false) async -> (RuntimeParams, AutotuneOutcome) {
        let base = RuntimeParams.oomSafeDefaults()
        return await recommendCore(spec: spec, base: base, timeoutSeconds: timeoutSeconds, trace: trace, dryRun: dryRun)
    }

    /// Testing helper allowing injection
    func recommendForTest(spec: ModelSpec,
                          base: RuntimeParams,
                          timeoutSeconds: Double,
                          trace: Bool,
                          injectedHasher: @escaping () async throws -> String,
                          injectedDeviceId: @escaping () -> String) async -> (RuntimeParams, AutotuneOutcome) {
        return await recommendCore(spec: spec, base: base, timeoutSeconds: timeoutSeconds, trace: trace, injectedHasher: injectedHasher, injectedDeviceId: injectedDeviceId)
    }
}
