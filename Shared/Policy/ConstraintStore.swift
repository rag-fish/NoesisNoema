//
//  ConstraintStore.swift
//  NoesisNoema
//
//  Created for EPIC1 Phase 4-B
//  Purpose: JSON persistence for policy constraints
//  License: MIT License
//

import Foundation

/// Errors that can occur during constraint storage operations
enum ConstraintStoreError: Error, LocalizedError {
    case writeFailed(underlyingError: Error)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let error):
            return "Failed to save constraints: \(error.localizedDescription)"
        }
    }
}

/// Persistent storage for policy constraints (PolicyRule)
/// Reads/writes JSON file in Application Support directory
final class ConstraintStore {

    // MARK: - Singleton

    static let shared = ConstraintStore()

    // MARK: - Properties

    private let fileURL: URL

    // MARK: - Initialization

    /// Initialize with optional custom file URL (for testing)
    /// - Parameter fileURL: Custom file URL (nil = default Application Support location)
    init(fileURL: URL? = nil) {
        if let fileURL = fileURL {
            self.fileURL = fileURL
        } else {
            // Default: Application Support directory
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!

            let noesisDir = appSupport.appendingPathComponent("NoesisNoema", isDirectory: true)
            try? FileManager.default.createDirectory(at: noesisDir, withIntermediateDirectories: true)

            self.fileURL = noesisDir.appendingPathComponent("policy-constraints.json")
        }
    }

    // MARK: - Public Methods

    /// Load policy rules from JSON file
    /// - Returns: Array of policy rules (empty if file doesn't exist)
    /// - Throws: Only throws if file exists but is corrupted beyond recovery
    func load() throws -> [PolicyRule] {
        // Scenario 1: File does not exist (expected on first launch)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("📄 Policy constraints file does not exist yet (first launch)")
            return []
        }

        // Scenario 2: File exists, attempt to load
        let data = try Data(contentsOf: fileURL)

        // Scenario 3: Decode JSON
        do {
            let decoder = JSONDecoder()
            let rules = try decoder.decode([PolicyRule].self, from: data)
            print("📄 Loaded \(rules.count) constraints from \(fileURL.lastPathComponent)")
            return rules
        } catch {
            // Scenario 4: Decoding failed (malformed JSON)
            print("⚠️ Failed to decode policy rules: \(error)")
            print("⚠️ Returning empty array (graceful degradation)")
            return []
        }
    }

    /// Save policy rules to JSON file
    /// - Parameter rules: Array of policy rules to save
    /// - Throws: ConstraintStoreError.writeFailed if file I/O fails
    func save(_ rules: [PolicyRule]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(rules)
            try data.write(to: fileURL, options: .atomic)
            print("✅ Saved \(rules.count) constraints to \(fileURL.lastPathComponent)")
        } catch {
            // Surface error to UI
            throw ConstraintStoreError.writeFailed(underlyingError: error)
        }
    }
}
