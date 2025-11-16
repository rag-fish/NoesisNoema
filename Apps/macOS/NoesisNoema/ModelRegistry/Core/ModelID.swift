// filepath: NoesisNoema/ModelRegistry/Core/ModelID.swift
// Project: NoesisNoema
// Description: Strongly-typed model identifier for type-safe Picker binding
// License: MIT License

import Foundation

/// Strongly-typed model identifier for SwiftUI Picker binding
struct ModelID: Hashable, Codable, Identifiable {
    let rawValue: String

    var id: String { rawValue }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(from spec: ModelSpec) {
        self.rawValue = spec.id
    }
}

extension ModelID: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self.rawValue = value
    }
}
