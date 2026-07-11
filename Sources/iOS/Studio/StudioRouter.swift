// StudioRouter.swift — native navigation shell for the Studio app (ported from studio/shell.jsx).
// The prototype's device-switcher / screen-menu chrome is prototype-only; the real app navigates
// via in-screen buttons. StudioModel holds the current screen + theme mode and the flow order.

import SwiftUI
import SwiftData

enum StudioScreen: String, CaseIterable {
    case library, mode, briefing, quality, review, compute, viewer, export, settings

    var title: String {
        switch self {
        case .library: return "Library"
        case .mode: return "New Scan"
        case .briefing: return "Briefing"
        case .quality: return "Detail"
        case .review: return "Review"
        case .compute: return "Compute"
        case .viewer: return "Model"
        case .export: return "Export"
        case .settings: return "Settings"
        }
    }

    static func auditLaunchScreen(environment: [String: String]) -> StudioScreen? {
        environment["THREEDSEEN_UI_AUDIT_SCREEN"].flatMap(StudioScreen.init(rawValue:))
    }
}

final class StudioModel: ObservableObject {
    @Published var screen: StudioScreen
    @Published var activeScanID: UUID?
    /// The requested reconstruction tier travels with a Mac handoff. On-device RealityKit
    /// currently supports only reduced detail, and the local compute service records that fact.
    @Published var selectedDetailTier = SettingsStore.QualityTier.full.rawValue
    @Published var selectedCaptureModeID = SettingsStore.DefaultMode.object.rawValue

    /// Natural walkthrough order (matches FLOWS.phone in shell.jsx).
    let flow: [StudioScreen] = [.library, .mode, .briefing, .quality,
                                .review, .compute, .viewer, .export, .settings]

    init(initialScreen: StudioScreen = .library) {
        screen = initialScreen
    }

    func go(_ s: StudioScreen) { withAnimation(.easeOut(duration: 0.22)) { screen = s } }

    /// Starts a distinct capture flow with the user's persisted defaults. Subsequent back/forward
    /// navigation keeps any per-scan overrides until the user starts another scan from Library.
    func beginNewScan(using settings: SettingsStore) {
        selectedCaptureModeID = settings.defaultMode.rawValue
        selectedDetailTier = settings.qualityTier.rawValue
        activeScanID = nil
        go(.mode)
    }
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
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var savedScans: [ScanSession]
    @StateObject private var model: StudioModel

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        #if DEBUG
        let initialScreen = StudioScreen.auditLaunchScreen(environment: environment) ?? .library
        #else
        let initialScreen = StudioScreen.library
        #endif
        _model = StateObject(wrappedValue: StudioModel(initialScreen: initialScreen))
    }

    /// Effective dark flag — `SettingsStore.appearance` is the single source of truth;
    /// `.system` resolves against the live system color scheme.
    private var dark: Bool {
        switch settings.appearance {
        case .light: return false
        case .dark: return true
        case .system: return systemScheme == .dark
        }
    }
    private var theme: Theme { dark ? .dark : .light }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            currentScreen
                .environmentObject(model)
                .id(model.screen)             // re-mount on screen change for the entrance
                .transition(.opacity)
        }
        .environment(\.theme, theme)
        .preferredColorScheme(settings.colorScheme)
        .task { repairRelocatedAssetURLs() }
    }

    private func repairRelocatedAssetURLs() {
        guard let store = try? ScanAssetStore() else { return }
        savedScans.forEach { store.repairPersistedURLs(on: $0) }
        try? modelContext.save()
    }

    @ViewBuilder private var currentScreen: some View {
        switch model.screen {
        case .library:    LibraryScreen()
        case .mode:       ModePickerScreen()
        case .briefing:   BriefingScreen()
        case .quality:    QualityScreen()
        case .review:     ReviewScreen()
        case .compute:    ComputeScreen()
        case .viewer:     ViewerScreen()
        case .export:     ExportScreen()
        case .settings:   SettingsScreen()
        }
    }
}
