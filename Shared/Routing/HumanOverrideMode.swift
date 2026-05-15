// NoesisNoema is a knowledge graph framework for building AI applications.
// This file defines HumanOverrideMode for runtime routing control.
// Created: 2026-05-15 (Phase 1, Issue #69)
// License: MIT License

import Foundation

/// Human-initiated routing override.
///
/// This is runtime control metadata, not request content.
/// It is passed separately from NoemaRequest and applied by
/// HybridExecutionCoordinator after PolicyEngine evaluation,
/// overwriting the effective PolicyAction with the highest priority.
///
/// Naming note:
///   .forceRemote is the user-facing / runtime-level name.
///   Internally it maps to PolicyAction.forceCloud, preserving
///   the existing Router and PolicyEngine vocabulary.
enum HumanOverrideMode: String, Codable, Equatable {
    /// No override. Normal policy evaluation and routing apply.
    case none

    /// Force local execution regardless of policy, privacy, or auto logic.
    /// Maps to PolicyAction.forceLocal.
    case forceLocal

    /// Force remote (cloud) execution regardless of policy, privacy, or auto logic.
    /// Maps to PolicyAction.forceCloud internally.
    case forceRemote
}
