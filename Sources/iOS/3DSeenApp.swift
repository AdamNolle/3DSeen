import SwiftUI
import SwiftData

@main
struct ThreeDSeenApp: App {
    @StateObject private var stateMachine = ProcessingStateMachine()
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            StudioRoot()
                .environmentObject(stateMachine)
                .environmentObject(settings)
        }
        .modelContainer(for: ScanSession.self)
    }
}
