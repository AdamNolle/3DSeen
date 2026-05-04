import SwiftUI

struct ContentView: View {
    @EnvironmentObject var stateMachine: ProcessingStateMachine
    @State private var selection: String? = "queue"
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Compute") {
                    NavigationLink(value: "queue") {
                        Label("Render Queue", systemImage: "tray.full")
                    }
                }
                
                Section("Assets") {
                    NavigationLink(value: "library") {
                        Label("Scan Library", systemImage: "photo.on.rectangle.angled")
                    }
                    NavigationLink(value: "materials") {
                        Label("Material Overrides", systemImage: "swirl.circle.righthalf.filled")
                    }
                }
            }
            .navigationTitle("3DSeen")
            .listStyle(.sidebar)
        } detail: {
            if selection == "queue" {
                VStack(spacing: 20) {
                    Image(systemName: "macstudio")
                        .font(.system(size: 100, weight: .light))
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .blue.opacity(0.3), radius: 20, y: 10)
                    
                    Text("Waiting for iPhone Hand-off...")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    
                    Text("Ensure your iPhone is on the same local network.\n3DSeen will automatically transfer heavy photogrammetry ZIPs here.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            } else {
                Text("Select an item from the sidebar.")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
        // Minimal Mac window styling
        .toolbar {
            ToolbarItem(placement: .status) {
                Text(stateMachine.connectedPeersDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// Small helper for the toolbar
extension ProcessingStateMachine {
    var connectedPeersDescription: String {
        // In reality, this would read from NetworkHandoffManager
        "Listening on _3dseen._tcp"
    }
}

#Preview {
    ContentView()
        .environmentObject(ProcessingStateMachine())
}
