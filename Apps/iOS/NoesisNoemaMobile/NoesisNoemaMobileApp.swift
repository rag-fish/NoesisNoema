//
//  NoesisNoemaMobileApp.swift
//  NoesisNoemaMobile
//
//  Created by Раскольников on 2025/08/15.
//

import SwiftUI

@main
struct NoesisNoemaMobileApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Hybrid Runtime: Primary execution coordinator
    private let executionCoordinator: ExecutionCoordinating

    init() {
        // Hybrid routing is the default execution pipeline
        self.executionCoordinator = HybridExecutionCoordinator()
    }

    var body: some Scene {
        WindowGroup {
            RootView(executionCoordinator: executionCoordinator)
        }
    }
}
