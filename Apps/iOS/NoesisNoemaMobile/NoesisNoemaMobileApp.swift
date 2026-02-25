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

    // EPIC1 Phase 4-A: ExecutionCoordinator instantiated at App level
    // Single long-lived instance, not created in View body
    private let executionCoordinator = ExecutionCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(executionCoordinator)
        }
    }
}
