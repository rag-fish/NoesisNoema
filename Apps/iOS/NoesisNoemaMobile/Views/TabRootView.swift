//
//  TabRootView.swift
//  NoesisNoemaMobile
//
//  Created by Раскольников on 2025/11/27.
//

import SwiftUI

struct TabRootView: View {
    /// App-level hybrid runtime entry point, threaded from @main via RootView.
    let executionCoordinator: ExecutionCoordinating

    /// One shared store for all tabs — questions asked on the Chat tab
    /// (MobileHomeView) appear in History, and Settings imports the same store.
    @StateObject private var documentManager = DocumentManager()
    @State private var selectedTab = 0

    // Keep in sync with TabBarView height
    private let tabBarHeight: CGFloat = 60

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 1:
                    HistoryView(documentManager: documentManager)
                case 2:
                    SettingsView(documentManager: documentManager)
                default:
                    // Tab 0 (and fallback): the full chat screen with the
                    // Model/Preset header. Routes inference through the shared
                    // app-level coordinator (no per-view news-up).
                    MobileHomeView(
                        documentManager: documentManager,
                        executionCoordinator: executionCoordinator
                    )
                }
            }
            .padding(.bottom, tabBarHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            TabBarView(selectedTab: $selectedTab)
                .frame(height: tabBarHeight)
        }
        .background(Color(.systemBackground))
    }
}

#Preview {
    TabRootView(executionCoordinator: HybridExecutionCoordinator())
}
