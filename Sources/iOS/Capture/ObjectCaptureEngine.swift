import SwiftUI
import RealityKit
import os

struct ObjectCaptureEngine: View {
    @EnvironmentObject var stateMachine: ProcessingStateMachine

    // We instantiate the actual iOS 17 ObjectCaptureSession
    @State private var session = ObjectCaptureSession()

    var body: some View {
        ZStack {
            // The native RealityKit Capture View driving the AR session
            ObjectCaptureView(session: session)
                .ignoresSafeArea()

            VStack {
                // Top HUD
                HStack {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 24))
                    Text("Object Capture")
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.top, 10)

                Spacer()

                if case .ready = session.state {
                    Button(action: {
                        session.startDetecting()
                    }) {
                        Text("Start Auto-Detection")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .shadow(color: .blue.opacity(0.3), radius: 10, y: 5)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 20)
                }

                if case .detecting = session.state {
                    Text("Walk around the object slowly to build the bounding box.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                        .padding(.bottom, 20)

                    Button(action: {
                        session.startCapturing()
                    }) {
                        Text("Start Capturing")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.green)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .shadow(color: .green.opacity(0.3), radius: 10, y: 5)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 20)
                }

                if case .capturing = session.state {
                    Button(action: {
                        session.finish()
                        // Route completion to our State Machine.
                        // TODO(Phase D): pass the real captured-images directory; temp dir for now.
                        stateMachine.send(.finishCapture(scanDataURL: URL(fileURLWithPath: NSTemporaryDirectory())))
                    }) {
                        Text("Finish Capture")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.red)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .shadow(color: .red.opacity(0.3), radius: 10, y: 5)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            // Provide a directory to save images
            let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var configuration = ObjectCaptureSession.Configuration()
            configuration.checkpointDirectory = directory
            session.start(imagesDirectory: directory, configuration: configuration)
        }
        .onDisappear {
            session.cancel()
        }
    }
}
