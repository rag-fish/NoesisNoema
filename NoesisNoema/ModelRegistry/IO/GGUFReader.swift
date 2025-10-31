// filepath: NoesisNoema/ModelRegistry/IO/GGUFReader.swift
// Project: NoesisNoema
// Description: GGUF metadata reader (Swift-only)

import Foundation

enum GGUFReader {
    enum GGUFError: Error, LocalizedError {
        case invalidFile
        case ioError(String)

        var errorDescription: String? {
            switch self {
            case .invalidFile: return "Invalid GGUF file"
            case .ioError(let msg): return "I/O error: \(msg)"
            }
        }
    }

    /// Check GGUF magic (ASCII "GGUF" -> 0x47 0x47 0x55 0x46); little-endian UInt32 = 0x4655_4747
    static func isValidGGUFFile(at path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        do {
            let data = try handle.read(upToCount: 4) ?? Data()
            if data.count < 4 { return false }
            let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }
            return magic == 0x4655_4747
        } catch {
            return false
        }
    }

    /// Read GGUF metadata via header validation and filename heuristics
    static func readMetadata(from path: String) async throws -> GGUFMetadata {
        guard isValidGGUFFile(at: path) else { throw GGUFError.invalidFile }
        let url = URL(fileURLWithPath: path)
        let fileName = url.lastPathComponent
        let lower = fileName.lowercased()

        // File size
        let sizeBytes: UInt64 = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0

        // Architecture inference
        let arch: String = {
            if lower.contains("llama") { return "llama" }
            if lower.contains("qwen") { return "qwen" }
            if lower.contains("phi") { return "phi" }
            if lower.contains("gemma") { return "gemma" }
            if lower.contains("mistral") { return "mistral" }
            if lower.contains("gpt") { return "gpt" }
            return "unknown"
        }()

        // Quantization inference
        let quant: String = {
            let patterns = ["q2_k","q3_k_s","q3_k_m","q3_k_l","q4_0","q4_1","q4_k_s","q4_k_m","q4_k_xl","q5_0","q5_1","q5_k_s","q5_k_m","q6_k","q8_0","f16","f32"]
            for p in patterns { if lower.contains(p) { return p.uppercased() } }
            return "unknown"
        }()

        // Parameter count (e.g., 4b, 20b, 70b) from filename
        let paramB: Double = {
            let seps = CharacterSet(charactersIn: "-_ .")
            let tokens = lower.components(separatedBy: seps)
            for t in tokens where t.hasSuffix("b") {
                if let num = Double(t.dropLast()) { return num }
            }
            // rough fallback from size (Q4 ≈ 0.5 byte/param)
            let approxParams = sizeBytes > 0 ? Double(sizeBytes) / 0.5 : 0
            return max(1.0, approxParams / 1e9)
        }()

        // Context length guess
        let nCtx: UInt32 = lower.contains("32768") ? 32768 : (lower.contains("8192") ? 8192 : (lower.contains("4096") ? 4096 : 2048))

        return GGUFMetadata(
            architecture: arch,
            parameterCount: paramB,
            contextLength: nCtx,
            modelSizeBytes: sizeBytes,
            quantization: quant,
            vocabSize: 32000,
            layerCount: 32,
            embeddingDimension: 4096,
            feedForwardDimension: 11008,
            attentionHeads: 32,
            supportsFlashAttention: false
        )
    }
}
