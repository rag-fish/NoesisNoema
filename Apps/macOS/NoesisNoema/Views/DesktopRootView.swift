//
//  DesktopRootView.swift
//  NoesisNoema (macOS)
//
//  ADR-0010: macOS UI Restoration — Native NavigationSplitView Architecture.
//
//  The macOS render path. A `NavigationSplitView` shell with a sidebar
//  (Chat / History / Settings) and a detail pane. This replaces the
//  `MinimalClientView`-only render path at `@main` (Shared/NoesisNoemaApp.swift)
//  and the retired `Shared/ContentView.swift` v0.22 UI.
//
//  Mirrors the iOS Phase 1 (PR #87) architecture for PATTERNS only — the macOS
//  view layer is duplicated by design (ADR-0010 §5): iOS view files use
//  iOS-only `Color(.systemBackground)` and a bottom-tab layout, so this layer
//  is written fresh with macOS-appropriate semantic colours and a split-view
//  shell. The whole file is `#if os(macOS)`-guarded because the enclosing
//  folder (`Apps/macOS/NoesisNoema`) is also synchronized into the iOS target
//  (NoesisNoemaMobile); the guard keeps it out of the iOS compile, the same
//  convention `Shared/ContentView.swift` uses.
//

#if os(macOS)
import SwiftUI

struct DesktopRootView: View {
    /// App-level hybrid runtime entry point, threaded from `@main`. ALL
    /// inference flows through this coordinator (ADR-0010 §3 / ADR-0008 R2);
    /// no view news-up a coordinator or calls `ModelManager.generateAsync*`.
    let executionCoordinator: ExecutionCoordinating

    /// The single shared QA/document store. Owned here so the Chat, History,
    /// and Settings sections all observe the SAME instance — questions asked in
    /// Chat appear in History, and Settings clears the same store. The iOS
    /// Phase 1 PR #87 had to fix exactly this (one shared store via injection);
    /// owning it once at the root and passing it down preserves that fix.
    @StateObject private var documentManager = DocumentManager()

    /// Sidebar selection. Optional to satisfy `List(selection:)`; the detail
    /// pane falls back to `.chat` when nothing is selected.
    @State private var section: DesktopSection? = .chat

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(DesktopSection.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            .navigationTitle("Noesis Noema")
        } detail: {
            detailPane
                .frame(minWidth: 480, minHeight: 420)
        }
        // SafeTextInput (the macOS IME-safe input used by DesktopChatView) reads
        // AppSettings from the environment, and the offline indicator binds to
        // it. Inject the shared instance once at the root.
        .environmentObject(AppSettings.shared)
    }

    @ViewBuilder
    private var detailPane: some View {
        switch section ?? .chat {
        case .chat:
            DesktopChatView(
                documentManager: documentManager,
                executionCoordinator: executionCoordinator
            )
        case .history:
            DesktopHistoryView(documentManager: documentManager)
        case .settings:
            DesktopSettingsView(documentManager: documentManager)
        }
    }
}

/// The three macOS sidebar sections. No bottom tab bar (ADR-0010 §2).
enum DesktopSection: String, CaseIterable, Identifiable, Hashable {
    case chat
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .history: return "History"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .history: return "clock"
        case .settings: return "gearshape"
        }
    }
}

#Preview {
    DesktopRootView(executionCoordinator: HybridExecutionCoordinator())
}
#endif
