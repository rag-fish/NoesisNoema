//
//  TabRootView.swift
//  NoesisNoemaMobile
//
//  Created by Раскольников on 2025/11/27.
//

import SwiftUI

struct TabRootView: View {
    @StateObject private var documentManager = DocumentManager()
    @State private var selectedTab = 0

    // Keep in sync with TabBarView height
    private let tabBarHeight: CGFloat = 60

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 0:
                    let view: ChatView = ChatView(documentManager: documentManager)
                    view
                case 1:
                    let view: HistoryView = HistoryView(documentManager: documentManager)
                    view
                case 2:
                    let view: SettingsView = SettingsView(documentManager: documentManager)
                    view
                default:
                    let view: ChatView = ChatView(documentManager: documentManager)
                    view
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
    TabRootView()
}
