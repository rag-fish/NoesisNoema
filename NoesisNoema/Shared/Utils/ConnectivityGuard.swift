// filepath: NoesisNoema/Shared/Utils/ConnectivityGuard.swift
// Comments: English

import Foundation

enum ConnectivityGuardError: Error, LocalizedError {
    case offline(message: String)
    var errorDescription: String? {
        switch self {
        case .offline(let message): return message
        }
    }
}

struct ConnectivityGuard {
    /// Returns true if remote calls are allowed. If offline, returns false.
    static func canPerformRemoteCall() -> Bool {
        AppSettings.shared.offline == false
    }
    /// Throws if offline. Use in async call sites.
    static func requireOnline(_ message: String = "App is in Offline mode. Please disable Offline to allow network access.") throws {
        if AppSettings.shared.offline { throw ConnectivityGuardError.offline(message: message) }
    }
}
