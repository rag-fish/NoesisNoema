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

    // EPIC1 Phase 4-B: PolicyRulesStore and ExecutionCoordinator at App level
    // Single long-lived instances, not created in View body
    private let policyRulesStore = PolicyRulesStore()
    private let executionCoordinator: ExecutionCoordinator

    init() {
        // Inject PolicyRulesStore into ExecutionCoordinator
        // Phase 4-B: Injected but not used yet (Phase 5 will use for policy evaluation)
        self.executionCoordinator = ExecutionCoordinator(policyRulesProvider: policyRulesStore)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(executionCoordinator)
        }
    }
}
