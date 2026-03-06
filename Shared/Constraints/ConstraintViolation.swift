//
//  ConstraintViolation.swift
//  NoesisNoema
//
//  Created for EPIC2 Phase 1
//  Purpose: Define constraint violation errors
//  License: MIT License
//

import Foundation

/// Error thrown when a constraint validation fails
struct ConstraintViolation: Error, CustomStringConvertible {
    let constraint: ExecutionConstraint
    let reason: String

    var description: String {
        return "ConstraintViolation: \(constraint) - \(reason)"
    }
}
