import SwiftUI
import SwiftData

@main
struct ThreeDSeenApp: App {
    @StateObject private var stateMachine = ProcessingStateMachine()
    @StateObject private var settings = SettingsStore()
    @StateObject private var handoff = IOSHandoffCoordinator()

    var body: some Scene {
        WindowGroup {
            StudioRoot()
                .environmentObject(stateMachine)
                .environmentObject(settings)
                .environmentObject(handoff)
        }
        .modelContainer(for: ScanSession.self)
    }
}
