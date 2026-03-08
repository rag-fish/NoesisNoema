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
            MinimalClientView(executionCoordinator: executionCoordinator)
        }
    }
}
#endif
