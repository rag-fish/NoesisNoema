// NoesisNoema - noema-agent connection seam
// DebugRouteState — DEBUG-only observable state for route decision display
// Created: 2026-06-27
// License: MIT License

#if DEBUG
import Foundation

/// Lightweight singleton that carries the last agent route decision for
/// display in debug UI (MinimalClientView). Only compiled in DEBUG builds.
///
/// Updated by HybridExecutionCoordinator after each optional route
/// consultation. Observed by MinimalClientView via @ObservedObject.
@MainActor
final class DebugRouteState: ObservableObject {
    static let shared = DebugRouteState()

    /// Route string returned by the last POST /v1/route call (e.g. "local_echo").
    /// Empty string when no route consultation has occurred this session.
    @Published var lastRoute: String = ""

    /// Whether the last route came from the agent or was set locally (fallback).
    @Published var lastRouteSource: String = ""

    private init() {}

    func update(route: String, source: String) {
        lastRoute = route
        lastRouteSource = source
    }
}
#endif
