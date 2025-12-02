//
//  TabBarView.swift
//  NoesisNoemaMobile
//
//  Modern iOS bottom TabBar with proper SafeArea handling
//  2025 design system alignment
//

import SwiftUI

struct TabBarView: View {
    @Binding var selectedTab: Int

    var body: some View {
        HStack(spacing: 0) {
            TabBarItem(icon: "bubble.left.and.bubble.right", title: "Chat", isSelected: selectedTab == 0) {
                selectedTab = 0
            }

            TabBarItem(icon: "clock", title: "History", isSelected: selectedTab == 1) {
                selectedTab = 1
            }

            TabBarItem(icon: "gearshape", title: "Settings", isSelected: selectedTab == 2) {
                selectedTab = 2
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

struct TabBarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @State var selectedTab = 0
    TabBarView(selectedTab: $selectedTab)
}
