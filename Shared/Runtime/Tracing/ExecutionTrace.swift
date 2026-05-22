//
//  ExecutionTrace.swift
//  NoesisNoema
//
//  Purpose: Runtime observability for execution pipeline
//  License: MIT License
//

import Foundation

/// Captures runtime metadata for each execution
struct ExecutionTrace: Codable {
    let traceId: UUID
    let query: String
    let route: RoutingDecision
    let policy: PolicyTrace?
    let routing: RoutingTrace?
    /// Step-level routing trace. Populated only when RuntimeState.debugMode == true.
    /// nil in production (debugMode == false) — existing decoders are unaffected.
    let routingSteps: RoutingStepTrace?
    let executor: String
    let duration: TimeInterval
    let timestamp: Date
    let decisionReason: String?
    let error: String?
    /// Privacy Step 4.5 enforcement outcome (ADR-0008 Decision 4).
    /// `true`  → the request was privacy-local; the on-device, no-fallback
    ///           invariant was enforced (or a violation was refused).
    /// `false` → the privacy-enforcement step ran; request was not local-only.
    /// `nil`   → trace predates R3 (no privacy-enforcement step), or the
    ///           constructing coordinator does not run Step 4.5.
    /// Optional, so existing decoders (TraceQuery, persisted trace files) are
    /// unaffected by the missing key — mirrors how `routingSteps` was added.
    let privacyEnforced: Bool?
}
