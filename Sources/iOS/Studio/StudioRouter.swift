// StudioRouter.swift — native navigation shell for the Studio app (ported from studio/shell.jsx).
// The prototype's device-switcher / screen-menu chrome is prototype-only; the real app navigates
// via in-screen buttons. StudioModel holds the current screen + theme mode and the flow order.

import SwiftUI
import SwiftData

enum StudioScreen: String, CaseIterable {
    case library, mode, briefing, quality, capture, review, compute, viewer, export, settings

    var title: String {
        switch self {
        case .library: return "Library"
        case .mode: return "New Scan"
        case .briefing: return "Briefing"
        case .quality: return "Detail"
        case .capture: return "Capture"
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
    let flow: [StudioScreen] = [.library, .mode, .briefing, .quality, .capture,
                                .review, .compute, .viewer, .export, .settings]

    init(initialScreen: StudioScreen = .library) {
        screen = initialScreen
    }

    func go(_ s: StudioScreen) { withAnimation(.easeOut(duration: 0.22)) { screen = s } }

    func showCompletedScan(_ scanID: UUID) {
        activeScanID = scanID
        go(.viewer)
    }

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
    @EnvironmentObject private var stateMachine: ProcessingStateMachine
    @EnvironmentObject private var handoff: IOSHandoffCoordinator
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var savedScans: [ScanSession]
    @StateObject private var model: StudioModel
    @State private var pipelineErrorMessage: String?
    @State private var readyCompletion: HandoffCompletion?

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
            Text(model.screen.rawValue)
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("studio.screen.\(model.screen.rawValue)")
                .allowsHitTesting(false)
        }
        .environment(\.theme, theme)
        .preferredColorScheme(settings.colorScheme)
        .task {
            handoff.attach(modelContext: modelContext)
            repairRelocatedAssetURLs()
        }
        .onReceive(stateMachine.$state) { state in
            switch state {
            case .error(let message):
                pipelineErrorMessage = message
            case .thermalThrottled:
                pipelineErrorMessage = "On-device compute stopped because the device reached a serious thermal state. The scan was requeued and can be resumed after the device cools."
            default:
                break
            }
        }
        .onReceive(handoff.$lastErrorMessage) { message in
            if let message { pipelineErrorMessage = message }
        }
        .onReceive(handoff.$lastCompletion) { completion in
            guard let completion else { return }
            if model.screen == .compute {
                model.showCompletedScan(completion.scanID)
            } else {
                readyCompletion = completion
            }
        }
        .alert("3DSeen needs attention", isPresented: pipelineErrorPresented) {
            Button("Back") { recoverFromPipelineError() }
            Button("Library", role: .cancel) { returnToLibraryAfterError() }
        } message: {
            Text(pipelineErrorMessage ?? "The current operation could not continue.")
        }
        .alert("Approve Mac connection?", isPresented: invitationPresented) {
            Button("Reject", role: .destructive) { respondToFirstInvitation(accept: false) }
            Button("Approve") { respondToFirstInvitation(accept: true) }
        } message: {
            Text("\(handoff.pendingInvitations.first?.peer.displayName ?? "A Mac") wants to connect for local scan processing. Approve only a Mac you recognize.")
        }
        .alert("Confirm secure pairing", isPresented: pairingPresented) {
            Button("Reject", role: .destructive) { respondToFirstPairing(accept: false) }
            Button("Codes Match") { respondToFirstPairing(accept: true) }
        } message: {
            let request = handoff.pendingPairingRequests.first
            Text("Check that \(request?.peer.displayName ?? "the Mac") shows the same code: \(request?.code ?? "------"). Never approve a different code.")
        }
        .alert("Mac result ready", isPresented: resultReadyPresented) {
            Button("Later", role: .cancel) { readyCompletion = nil }
            Button("View Model") { showReadyCompletion() }
        } message: {
            Text("Reconstruction finished and the model was saved to your Library.")
        }
    }

    private var invitationPresented: Binding<Bool> {
        Binding(
            get: { !handoff.pendingInvitations.isEmpty },
            set: { if !$0, !handoff.pendingInvitations.isEmpty { respondToFirstInvitation(accept: false) } }
        )
    }

    private func respondToFirstInvitation(accept: Bool) {
        guard let invitation = handoff.pendingInvitations.first else { return }
        handoff.respond(to: invitation, accept: accept)
    }

    private var pairingPresented: Binding<Bool> {
        Binding(
            get: { !handoff.pendingPairingRequests.isEmpty },
            set: { if !$0, !handoff.pendingPairingRequests.isEmpty { respondToFirstPairing(accept: false) } }
        )
    }

    private func respondToFirstPairing(accept: Bool) {
        guard let request = handoff.pendingPairingRequests.first else { return }
        if accept {
            handoff.confirmPairing(request)
        } else {
            handoff.rejectPairing(request)
        }
    }

    private var resultReadyPresented: Binding<Bool> {
        Binding(
            get: { readyCompletion != nil },
            set: { if !$0 { readyCompletion = nil } }
        )
    }

    private func showReadyCompletion() {
        guard let completion = readyCompletion else { return }
        readyCompletion = nil
        model.showCompletedScan(completion.scanID)
    }

    private var pipelineErrorPresented: Binding<Bool> {
        Binding(
            get: { pipelineErrorMessage != nil },
            set: { if !$0 { pipelineErrorMessage = nil } }
        )
    }

    private func recoverFromPipelineError() {
        pipelineErrorMessage = nil
        handoff.clearError()
        stateMachine.send(.reset)
        switch model.screen {
        case .capture:
            model.go(.quality)
        case .compute:
            model.go(.review)
        default:
            break
        }
    }

    private func returnToLibraryAfterError() {
        pipelineErrorMessage = nil
        handoff.clearError()
        stateMachine.send(.reset)
        model.go(.library)
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
        case .capture:    CaptureScreen()
        case .review:     ReviewScreen()
        case .compute:    ComputeScreen()
        case .viewer:     ViewerScreen()
        case .export:     ExportScreen()
        case .settings:   SettingsScreen()
        }
    }
}
