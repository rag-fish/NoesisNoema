// filepath: NoesisNoema/Shared/ModelManager+Extensions.swift
// Project: NoesisNoema
// Description: ModelManager extensions for error recovery and streaming
// License: MIT License

import Foundation

/// ModelManager extensions for enhanced functionality
extension ModelManager {

    /// OOMリカバリー付きモデルロード
    func loadModelWithFallback(id: String) async throws {
        do {
            try await loadModel(id: id)
        } catch InferenceError.outOfMemory {
            // OOM検出時、縮小パラメータでリトライ
            SystemLog().logEvent(event: "[ModelManager] OOM detected, retrying with reduced params")

            if let spec = await registry.getModelSpec(id: id) {
                var reducedParams = spec.runtimeParams
                reducedParams.nCtx = reducedParams.nCtx / 2
                reducedParams.nBatch = reducedParams.nBatch / 2
                reducedParams.nGpuLayers = 0 // CPU強制

                await registry.updateRuntimeParams(for: id, params: reducedParams)

                errorMessage = "Retrying with reduced memory settings..."
                try await loadModel(id: id)
            }
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            SystemLog().logEvent(event: "[ModelManager] Load failed: \(error)")
            throw error
        }
    }

    /// Validate model compatibility before loading
    func validateModel(id: String) async -> ModelValidationResult? {
        guard let spec = await registry.getModelSpec(id: id) else {
            return nil
        }

        return await ModelFactory.validateModel(metadata: spec.metadata)
    }

    /// Streaming inference (generates token by token)
    func generateStream(prompt: String, maxTokens: Int32 = 512) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                guard let engine = getCurrentEngine() else {
                    continuation.finish(throwing: InferenceError.modelNotLoaded)
                    return
                }

                do {
                    try await engine.prepare(prompt: prompt)

                    var tokenCount: Int32 = 0
                    while await !engine.isDone && tokenCount < maxTokens {
                        if let token = try await engine.generateNextToken() {
                            continuation.yield(token)
                            tokenCount += 1
                        } else {
                            break
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// 全モデルの互換性レポート生成
    func generateCompatibilityReport() async -> String {
        var report = "# Model Compatibility Report\n\n"
        report += "Generated: \(Date())\n\n"

        let specs = await registry.getAllModelSpecs()

        for spec in specs {
            report += "## \(spec.name) (\(spec.id))\n"
            report += "- File: `\(spec.modelFile)`\n"
            report += "- Available: \(spec.isAvailable ? "✓ Yes" : "✗ No")\n"
            report += "- Architecture: \(spec.metadata.architecture)\n"
            report += "- Parameters: \(String(format: "%.1fB", spec.metadata.parameterCount))\n"
            report += "- Quantization: \(spec.metadata.quantization)\n"

            let validation = await ModelFactory.validateModel(metadata: spec.metadata)
            report += "- Status: \(validation.isCompatible ? "✓ Compatible" : "✗ Incompatible")\n"
            report += "- Est. Memory: \(String(format: "%.1fGB", validation.estimatedMemoryGB))\n"

            if validation.hasWarnings {
                report += "- Warnings:\n"
                for warning in validation.warnings {
                    report += "  - \(warning)\n"
                }
            }

            report += "\n"
        }

        return report
    }
}
