//
//  ConstraintViolation.swift
//  NoesisNoema
//
//  ConstraintViolation
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
