// filepath: ModelRegistry/IO/RegistryPersistence.swift
// Project: NoesisNoema
// File: RegistryPersistence.swift
// Description: Persist and load per-model runtime params (recommended/override) and last selection

import Foundation
import UniformTypeIdentifiers

enum RuntimeMode: String, Codable {
    case recommended
    case override
}

struct ModelRuntimeRecord: Codable {
    var recommended: RuntimeParams
    var overrideParams: RuntimeParams?
    var mode: RuntimeMode
}

struct PersistentRegistry: Codable {
    var lastSelectedModelId: String?
    var models: [String: ModelRuntimeRecord]

    init(lastSelectedModelId: String? = nil, models: [String: ModelRuntimeRecord] = [:]) {
        self.lastSelectedModelId = lastSelectedModelId
        self.models = models
    }
}

actor RegistryPersistence {
    static let shared = RegistryPersistence()

    // For tests: override base directory (e.g., /tmp/testdir)
    static var baseDirectoryOverride: URL?

    private var cached: PersistentRegistry?

    private func baseDirectoryURL() -> URL {
        if let o = RegistryPersistence.baseDirectoryOverride { return o }
        #if os(iOS)
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #else
        let home = FileManager.default.homeDirectoryForCurrentUser
        #endif
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("NoesisNoema", isDirectory: true)
    }

    private func fileURL() -> URL {
        return baseDirectoryURL().appendingPathComponent("registry.json", conformingTo: .json)
    }

    func load() async -> PersistentRegistry {
        if let cached { return cached }
        let url = fileURL()
        do {
            let data = try Data(contentsOf: url)
            let reg = try JSONDecoder().decode(PersistentRegistry.self, from: data)
            self.cached = reg
            return reg
        } catch {
            // Ensure directory exists
            do { try FileManager.default.createDirectory(at: baseDirectoryURL(), withIntermediateDirectories: true) } catch { /* ignore */ }
            let empty = PersistentRegistry()
            self.cached = empty
            return empty
        }
    }

    func save(_ reg: PersistentRegistry) async {
        let url = fileURL()
        do {
            try FileManager.default.createDirectory(at: baseDirectoryURL(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(reg)
            try data.write(to: url, options: [.atomic])
            self.cached = reg
        } catch {
            print("[RegistryPersistence] Save failed: \(error)")
        }
    }

    // Convenience helpers
    func updateRecord(modelId: String, mutate: (inout ModelRuntimeRecord?) -> Void) async {
        var reg = await load()
        var rec = reg.models[modelId]
        mutate(&rec)
        if let rec { reg.models[modelId] = rec } else { reg.models.removeValue(forKey: modelId) }
        await save(reg)
    }

    func setLastSelectedModel(id: String?) async {
        var reg = await load()
        reg.lastSelectedModelId = id
        await save(reg)
    }

    func getRecord(for modelId: String) async -> ModelRuntimeRecord? {
        let reg = await load()
        return reg.models[modelId]
    }

    func getLastSelectedModelId() async -> String? {
        let reg = await load()
        return reg.lastSelectedModelId
    }

    // Testing helpers
    func clearCache() {
        self.cached = nil
    }

    func wipe() async {
        let url = fileURL()
        do { try FileManager.default.removeItem(at: url) } catch { /* ignore */ }
        self.cached = nil
    }
}
