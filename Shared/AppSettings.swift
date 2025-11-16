// filepath: NoesisNoema/Shared/AppSettings.swift
// App-wide settings and feature flags
// Comments: English

import Foundation
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    @Published var offline: Bool = false // When true, all outbound network calls must be blocked
    @Published var disableMacOSIME: Bool = false // When true, disable macOS IME integration to prevent XPC decoding issues
    private init() {}
}
