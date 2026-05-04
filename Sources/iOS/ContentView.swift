import SwiftUI

struct ContentView: View {
    @EnvironmentObject var stateMachine: ProcessingStateMachine
    
    var body: some View {
        NavigationStack {
            if case let .capturing(mode) = stateMachine.state {
                CaptureCoordinatorView(captureMode: mode)
            } else {
                ZStack {
                    // Beautiful Mesh Gradient Background
                    LinearGradient(
                        colors: [Color.blue.opacity(0.4), Color.purple.opacity(0.3), Color.black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                    
                    VStack(spacing: 30) {
                        Spacer()
                        
                        // Glassmorphism Card
                        VStack(spacing: 20) {
                            Image(systemName: "camera.aperture")
                                .font(.system(size: 80, weight: .thin))
                                .foregroundStyle(
                                    .linearGradient(
                                        colors: [.white, .blue.opacity(0.8)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: .blue.opacity(0.5), radius: 10)
                            
                            Text("3DSeen")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            
                            Text(stateDescription)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.vertical, 40)
                        .padding(.horizontal, 60)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                        
                        Spacer()
                        
                        if stateMachine.state == .idle {
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    stateMachine.send(.startCapture(.autoPilot))
                                }
                            }) {
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text("Start Auto-Capture")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                                )
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                                .shadow(color: .blue.opacity(0.4), radius: 10, y: 5)
                            }
                            .padding(.horizontal, 40)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
        }
    }
    
    private var stateDescription: String {
        switch stateMachine.state {
        case .idle: return "Ready to Scan"
        case .captureModeSelection: return "Selecting Mode..."
        case .capturing(let mode): return "Capturing (\(mode.rawValue))"
        case .packagingScan: return "Packaging Data..."
        case .readyForCompute(let mode): return "Ready for \(mode.rawValue)"
        case .computingLocally(let progress): return String(format: "Computing (%.0f%%)", progress * 100)
        case .computingOffloaded(let status): return "Offloading: \(status)"
        case .completed: return "Render Complete"
        case .error(let message): return "Error: \(message)"
        case .thermalThrottled: return "Hardware Cooling..."
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ProcessingStateMachine())
}
