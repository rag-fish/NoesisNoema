//
//  ExecutionConstraint.swift
//  NoesisNoema
//
//  Created for EPIC2 Phase 1
//  Purpose: Define execution constraints for the ConstraintRuntime layer
//  License: MIT License
//

import Foundation

/// Execution constraints that can be applied to NoemaRequest validation
enum ExecutionConstraint: Equatable {
    /// Requires explicit user intent to be present
    case requiresUserIntent

    /// Maximum token limit for the request
    case maxTokens(Int)

    /// Disallows tool usage during execution
    case noToolUse
}
