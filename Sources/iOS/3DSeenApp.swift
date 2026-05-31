import SwiftUI
import SwiftData

@main
struct ThreeDSeenApp: App {
    @StateObject private var stateMachine = ProcessingStateMachine()

    var body: some Scene {
        WindowGroup {
            StudioRoot()
                .environmentObject(stateMachine)
        }
        .modelContainer(for: ScanSession.self)
    }
}
