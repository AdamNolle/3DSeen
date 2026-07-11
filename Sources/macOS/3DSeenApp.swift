import SwiftUI
import SwiftData

@main
struct ThreeDSeenMacApp: App {
    @StateObject private var stateMachine = ProcessingStateMachine()
    @StateObject private var nav = MacNav()

    var body: some Scene {
        WindowGroup {
            ContentView(nav: nav)
                .environmentObject(stateMachine)
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(for: ScanSession.self)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { nav.section = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
