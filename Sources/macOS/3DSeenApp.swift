import SwiftUI
import SwiftData

@main
struct ThreeDSeenMacApp: App {
    @StateObject private var stateMachine = ProcessingStateMachine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(stateMachine)
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(for: ScanSession.self)
    }
}
