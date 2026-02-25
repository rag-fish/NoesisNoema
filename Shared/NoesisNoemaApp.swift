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
    // EPIC1 Phase 4-A: ExecutionCoordinator instantiated at App level
    // Single long-lived instance, not created in View body
    private let executionCoordinator = ExecutionCoordinator()

    var body: some Scene {
        WindowGroup {
            MinimalClientView()
                .environmentObject(executionCoordinator)
        }
    }
}
#endif
