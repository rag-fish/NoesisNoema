// Project: NoesisNoema
// File: RegistryJSON.swift
// Description: JSON loader with validation for model registry

import Foundation

enum RegistryJSONError: Error, CustomStringConvertible {
    case invalidTopLevel
    case missingField(String)
    case typeMismatch(String)

    var description: String {
        switch self {
        case .invalidTopLevel: return "Top-level must be an array or an object with 'models' array"
        case .missingField(let f): return "Missing required field: \(f)"
        case .typeMismatch(let f): return "Field has invalid type: \(f)"
        }
    }
}

struct RegistryJSONLoader {
    /// Load registry from Data/URL/String with validation
    static func load(from data: Data) throws -> [ModelSpec] {
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        return try parseTopLevel(obj)
    }

    static func load(from url: URL) throws -> [ModelSpec] {
        let data = try Data(contentsOf: url)
        return try load(from: data)
    }

    static func load(from jsonString: String) throws -> [ModelSpec] {
        guard let data = jsonString.data(using: .utf8) else { throw RegistryJSONError.invalidTopLevel }
        return try load(from: data)
    }

    private static func parseTopLevel(_ obj: Any) throws -> [ModelSpec] {
        if let dict = obj as? [String: Any] {
            guard let arr = dict["models"] as? [Any] else { throw RegistryJSONError.invalidTopLevel }
            return try arr.enumerated().map { try parseModel($0.element, index: $0.offset) }
        } else if let arr = obj as? [Any] {
            return try arr.enumerated().map { try parseModel($0.element, index: $0.offset) }
        }
        throw RegistryJSONError.invalidTopLevel
    }

    private static func parseModel(_ any: Any, index: Int) throws -> ModelSpec {
        guard let m = any as? [String: Any] else { throw RegistryJSONError.typeMismatch("model[\(index)]") }
        func req<T>(_ key: String, as type: T.Type = T.self) throws -> T {
            guard let v = m[key] else { throw RegistryJSONError.missingField(key) }
            guard let cast = v as? T else { throw RegistryJSONError.typeMismatch(key) }
            return cast
        }
        func opt<T>(_ key: String) -> T? { m[key] as? T }

        let id: String = try req("id")
        let name: String = try req("name")
        // Both model_file and modelFile accepted
        let modelFile: String = (m["model_file"] as? String) ?? (m["modelFile"] as? String) ?? { _ in
            // throw if missing
            _ = try? req("model_file", as: String.self)
            return ""
        }(())
        if modelFile.isEmpty { throw RegistryJSONError.missingField("model_file") }
        let version: String = try req("version")
        let quant: String = (m["quantization"] as? String) ?? (m["quant"] as? String) ?? {
            _ = try? req("quantization", as: String.self)
            return ""
        }()
        if quant.isEmpty { throw RegistryJSONError.missingField("quantization") }

        // Optional metadata hints
        let paramsB: Double? = (m["parameter_count_b"] as? Double) ?? (m["parameters_b"] as? Double)
        let ctxLen: UInt32? = (m["context_length"] as? UInt32) ?? ((m["context_length"] as? Int).map { UInt32($0) })

        let metadata = GGUFMetadata(
            architecture: (m["architecture"] as? String) ?? "unknown",
            parameterCount: paramsB ?? 0.0,
            contextLength: ctxLen ?? 2048,
            modelSizeBytes: 0,
            quantization: quant,
            vocabSize: 32000,
            layerCount: (m["layers"] as? UInt32) ?? 32,
            embeddingDimension: (m["embedding_dim"] as? UInt32) ?? 4096,
            feedForwardDimension: (m["ff_dim"] as? UInt32) ?? 11008,
            attentionHeads: (m["heads"] as? UInt32) ?? 32,
            supportsFlashAttention: (m["flash_attention"] as? Bool) ?? false
        )

        // Runtime overrides
        var runtime = RuntimeParams.oomSafeDefaults()
        if let rt = m["runtime"] as? [String: Any] {
            if let nThreads = rt["n_threads"] as? Int { runtime.nThreads = Int32(nThreads) }
            if let nGpuLayers = rt["n_gpu_layers"] as? Int { runtime.nGpuLayers = Int32(nGpuLayers) }
            if let nBatch = rt["n_batch"] as? Int { runtime.nBatch = UInt32(nBatch) }
            if let nCtx = rt["n_ctx"] as? Int { runtime.nCtx = UInt32(nCtx) }
            if let temp = rt["temperature"] as? Double { runtime.temperature = Float(temp) }
            if let topK = rt["top_k"] as? Int { runtime.topK = Int32(topK) }
            if let topP = rt["top_p"] as? Double { runtime.topP = Float(topP) }
            if let rp = rt["repeat_penalty"] as? Double { /* not in struct; ignore or extend */ _ = rp }
            if let memMB = rt["memory_limit_mb"] as? Int { runtime.memoryLimitMB = UInt64(memMB) }
        }

        // Build spec with auto-tuned params (respect overrides where set)
        var spec = ModelSpec.withAutoTunedParams(
            id: id,
            name: name,
            modelFile: modelFile,
            version: version,
            metadata: metadata,
            filePath: nil
        )
        // Merge overrides
        if (m["runtime"] as? [String: Any]) != nil { spec.runtimeParams = runtime }
        // Tags/description
        if let tags = m["tags"] as? [String] { spec.tags = tags }
        if let desc = m["description"] as? String { spec.description = desc }
        return spec
    }
}
