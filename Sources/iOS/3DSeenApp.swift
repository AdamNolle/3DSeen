import SwiftUI
import SwiftData

@main
struct _DSeenApp: App {
    @StateObject private var stateMachine = ProcessingStateMachine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(stateMachine)
        }
        .modelContainer(for: ScanSession.self)
    }
}
