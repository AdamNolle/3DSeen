import SwiftUI

struct CaptureCoordinatorView: View {
    @EnvironmentObject var stateMachine: ProcessingStateMachine
    let captureMode: CaptureMode
    
    var body: some View {
        ZStack {
            // Underlay: This represents the camera feed
            Color.black.ignoresSafeArea()
            
            switch captureMode {
            case .object:
                ObjectCaptureEngine()
            case .space:
                RoomCaptureEngine()
            case .landscape:
                LandscapeCaptureEngine()
            case .autoPilot:
                // Auto-pilot analyzes first, then falls back to object
                VStack(spacing: 20) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    
                    Text("Analyzing Scene...")
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    Text("Auto-Pilot active")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(40)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            stateMachine.send(.startCapture(.object))
                        }
                    }
                }
            }
            
            // Global overlay UI
            VStack {
                HStack {
                    Button(action: {
                        withAnimation {
                            stateMachine.send(.reset)
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding()
                    Spacer()
                }
                Spacer()
            }
        }
        .navigationBarBackButtonHidden()
    }
}
