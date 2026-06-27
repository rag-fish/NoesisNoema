// filepath: NoesisNoema/Shared/AppSettings.swift
// App-wide settings and feature flags
// Comments: English

import Foundation
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    @Published var offline: Bool = false // When true, all outbound network calls must be blocked
    @Published var disableMacOSIME: Bool = false // When true, disable macOS IME integration to prevent XPC decoding issues

    // MARK: - noema-agent connection seam (Issue #120)

    /// Feature flag: consult noema-agent POST /v1/route before local execution.
    ///
    /// Default: false — local RAG behavior is 100% unchanged when off.
    /// When true: the app calls POST /v1/route, logs the route decision, then
    /// always continues with local execution (remote inference not yet wired).
    /// Toggle in DesktopSettingsView / SettingsView (DEBUG display only).
    @Published var enableRemoteRouting: Bool = false

    /// Base URL of the locally running noema-agent instance.
    ///
    /// Only consulted when `enableRemoteRouting` is true.
    /// Default: http://localhost:8080 (noema-agent default port).
    @Published var agentBaseURL: String = "http://localhost:8080"

    private init() {}
}
