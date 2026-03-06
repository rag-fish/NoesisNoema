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
        MinimalClientView(executionCoordinator: executionCoordinator)
    }
}

#Preview {
    RootView(executionCoordinator: ExecutionCoordinator())
}
