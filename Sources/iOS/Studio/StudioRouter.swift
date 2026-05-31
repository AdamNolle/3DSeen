// StudioRouter.swift — native navigation shell for the Studio app (ported from studio/shell.jsx).
// The prototype's device-switcher / screen-menu chrome is prototype-only; the real app navigates
// via in-screen buttons. StudioModel holds the current screen + theme mode and the flow order.

import SwiftUI

enum StudioScreen: String, CaseIterable {
    case library, mode, briefing, viewfinder, quality, review, compute, viewer, export, settings

    var title: String {
        switch self {
        case .library: return "Library"
        case .mode: return "New Scan"
        case .briefing: return "Briefing"
        case .viewfinder: return "Capture"
        case .quality: return "Detail"
        case .review: return "Review"
        case .compute: return "Compute"
        case .viewer: return "Model"
        case .export: return "Export"
        case .settings: return "Settings"
        }
    }
}

final class StudioModel: ObservableObject {
    @Published var screen: StudioScreen = .library
    @Published var dark: Bool = false

    /// Natural walkthrough order (matches FLOWS.phone in shell.jsx).
    let flow: [StudioScreen] = [.library, .mode, .briefing, .viewfinder, .quality,
                                .review, .compute, .viewer, .export, .settings]

    func go(_ s: StudioScreen) { withAnimation(.easeOut(duration: 0.22)) { screen = s } }
    func next() {
        guard let i = flow.firstIndex(of: screen), i < flow.count - 1 else { return }
        go(flow[i + 1])
    }
    func prev() {
        guard let i = flow.firstIndex(of: screen), i > 0 else { return }
        go(flow[i - 1])
    }
}

struct StudioRoot: View {
    @StateObject private var model = StudioModel()

    private var theme: Theme { model.dark ? .dark : .light }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            currentScreen
                .environmentObject(model)
                .id(model.screen)             // re-mount on screen change for the entrance
                .transition(.opacity)
        }
        .environment(\.theme, theme)
        .preferredColorScheme(model.dark ? .dark : .light)
    }

    @ViewBuilder private var currentScreen: some View {
        switch model.screen {
        case .library:    LibraryScreen()
        case .mode:       ModePickerScreen()
        case .briefing:   BriefingScreen()
        case .viewfinder: ViewfinderScreen()
        case .quality:    QualityScreen()
        case .review:     ReviewScreen()
        case .compute:    ComputeScreen()
        case .viewer:     ViewerScreen()
        case .export:     ExportScreen()
        case .settings:   SettingsScreen()
        }
    }
}
