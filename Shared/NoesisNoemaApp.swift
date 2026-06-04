//
//  NoesisNoemaApp.swift
//  NoesisNoema
//
//  Created by Раскольников on 2025/07/18.
//

import SwiftUI

#if os(macOS)
@main
struct NoesisNoemaApp: App {
    // Hybrid Runtime: Primary execution coordinator
    private let executionCoordinator: ExecutionCoordinating

    init() {
        // Hybrid routing is the default execution pipeline
        self.executionCoordinator = HybridExecutionCoordinator()
    }

    var body: some Scene {
        WindowGroup {
            // ADR-0010: the macOS render path is the full NavigationSplitView UI
            // (Chat / History / Settings). The app-level coordinator created
            // above is threaded down; DesktopRootView owns the single shared
            // DocumentManager. MinimalClientView remains reachable from
            // Settings ▸ Advanced under #if DEBUG, and the retired
            // Shared/ContentView.swift is no longer referenced.
            DesktopRootView(executionCoordinator: executionCoordinator)
        }
    }
}
#endif
