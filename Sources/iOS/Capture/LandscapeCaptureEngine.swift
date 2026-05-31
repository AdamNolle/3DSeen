import SwiftUI
import ARKit
import RealityKit
import OSLog

/// Outdoor / landscape capture. LiDAR is unreliable in direct sun, so this uses pure
/// ARKit visual-inertial odometry (VIO) world tracking and writes well-spaced, sharp frames
/// to a folder that PhotogrammetrySession consumes downstream.
struct LandscapeCaptureEngine: View {
    @EnvironmentObject var stateMachine: ProcessingStateMachine
    @StateObject private var capture = LandscapeCaptureController()

    var body: some View {
        ZStack {
            LandscapeARView(controller: capture).ignoresSafeArea()

            VStack {
                HStack {
                    Image(systemName: "mountain.2").font(.system(size: 24))
                    Text("Landscape · VIO").font(.headline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(.ultraThinMaterial).clipShape(Capsule())
                .padding(.top, 10)

                // live frame counter
                Text("\(capture.frameCount) frames · \(capture.trackingState)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(.ultraThinMaterial).clipShape(Capsule())
                    .padding(.top, 8)

                Spacer()

                Text("LiDAR off · VIO world tracking. Walk a smooth arc; frames captured automatically.")
                    .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.white)
                    .padding().background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 15)).padding(.bottom, 20)

                Button {
                    let folder = capture.finish()
                    stateMachine.send(.finishCapture(scanDataURL: folder))
                } label: {
                    Text("Finish Landscape Scan")
                        .font(.headline).frame(maxWidth: .infinity).padding()
                        .background(Color.orange.opacity(0.9)).foregroundColor(.white)
                        .clipShape(Capsule()).shadow(color: .orange.opacity(0.3), radius: 10, y: 5)
                }
                .padding(.horizontal, 40).padding(.bottom, 40)
            }
        }
        .onDisappear { capture.stop() }
    }
}

/// Drives the ARSession and saves well-spaced sharp frames to disk for photogrammetry.
final class LandscapeCaptureController: NSObject, ObservableObject, ARSessionDelegate {
    private let logger = Logger(subsystem: "com.adamnolle.3DSeen", category: "Landscape")
    let session = ARSession()
    private let ciContext = CIContext()

    @Published var frameCount = 0
    @Published var trackingState = "starting"

    private(set) var captureFolder: URL
    private var lastCapturePosition: SIMD3<Float>?
    private var lastCaptureTime: TimeInterval = 0
    private let minTranslation: Float = 0.08   // metres between frames
    private let minInterval: TimeInterval = 0.25

    override init() {
        captureFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("landscape-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: captureFolder, withIntermediateDirectories: true)
        super.init()
        session.delegate = self
        start()
    }

    func start() {
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        config.planeDetection = []
        // VIO only — no scene reconstruction / LiDAR mesh outdoors.
        if type(of: config).supportsFrameSemantics(.smoothedSceneDepth) == false {
            config.frameSemantics = []
        }
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() { session.pause() }

    /// Stops capture and returns the folder of captured frames.
    func finish() -> URL {
        session.pause()
        logger.info("Landscape capture finished: \(self.frameCount) frames in \(self.captureFolder.lastPathComponent)")
        return captureFolder
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        DispatchQueue.main.async {
            switch camera.trackingState {
            case .normal: self.trackingState = "tracking"
            case .limited: self.trackingState = "limited"
            case .notAvailable: self.trackingState = "no tracking"
            }
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard case .normal = frame.camera.trackingState else { return }
        let t = frame.timestamp
        guard t - lastCaptureTime >= minInterval else { return }

        let pos = frame.camera.transform.columns.3
        let position = SIMD3<Float>(pos.x, pos.y, pos.z)
        if let last = lastCapturePosition, simd_distance(last, position) < minTranslation { return }

        lastCaptureTime = t
        lastCapturePosition = position
        saveFrame(frame.capturedImage)
    }

    private func saveFrame(_ pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cg = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let index = frameCount
        let url = captureFolder.appendingPathComponent(String(format: "frame_%04d.jpg", index))
        DispatchQueue.global(qos: .utility).async {
            #if canImport(UIKit)
            if let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.92) {
                try? data.write(to: url)
            }
            #endif
        }
        DispatchQueue.main.async { self.frameCount += 1 }
    }
}

/// Hosts an ARView running the landscape capture session.
struct LandscapeARView: UIViewRepresentable {
    let controller: LandscapeCaptureController
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = controller.session
        return view
    }
    func updateUIView(_ uiView: ARView, context: Context) {}
}
