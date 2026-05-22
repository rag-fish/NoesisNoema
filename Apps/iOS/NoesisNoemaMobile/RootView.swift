//
//  RootView.swift
//  NoesisNoemaMobile
//
//  Created by Раскольников on 2025/08/15.
//

import SwiftUI

struct RootView: View {
    let executionCoordinator: ExecutionCoordinating

    var body: some View {
        // Phase 1: render the full tabbed UI (Chat / History / Settings).
        // The app-level executionCoordinator from @main is threaded through.
        // MinimalClientView (the EPIC1 vertical-slice MVP) remains reachable
        // as a debug screen via SettingsView ▸ Advanced (DEBUG builds).
        TabRootView(executionCoordinator: executionCoordinator)
    }
}

#Preview {
    RootView(executionCoordinator: HybridExecutionCoordinator())
}
