import SwiftUI
import ARKit
import RealityKit
import OSLog

/// Outdoor / landscape capture. LiDAR is unreliable in direct sun, so this uses pure
/// ARKit visual-inertial odometry (VIO) world tracking and writes well-spaced, sharp frames
/// to a folder that PhotogrammetrySession consumes downstream.
struct LandscapeCaptureEngine: View {
    @EnvironmentObject var stateMachine: ProcessingStateMachine
    let attemptID: UUID
    @StateObject private var capture = LandscapeCaptureController()

    var body: some View {
        ZStack {
            LandscapeARView(controller: capture).ignoresSafeArea()

            LiveCaptureHUD(status: captureStatus, onFinish: finishCapture)
                .allowsHitTesting(!capture.isFinishing)
        }
        .onDisappear { capture.stop(discardUnsealedCapture: true) }
    }

    private var captureStatus: LiveCaptureStatus {
        LiveCaptureStatus(
            mode: .landscape,
            phase: capture.isFinishing ? .finalizing : .capturing,
            frameCount: capture.frameCount,
            trackingStatus: capture.trackingState
        )
    }

    private func finishCapture() {
        capture.finish { result in
            switch result {
            case .success(let folder):
                stateMachine.send(.finishCapture(scanDataURL: folder, attemptID: attemptID))
            case .failure(let error):
                stateMachine.send(.errorOccurred(error.localizedDescription))
            }
        }
    }
}

/// Drives the ARSession and saves well-spaced sharp frames to disk for photogrammetry.
final class LandscapeCaptureController: NSObject, ObservableObject, ARSessionDelegate {
    private let logger = Logger(subsystem: "com.adamnolle.3DSeen", category: "Landscape")
    let session = ARSession()
    private let ciContext = CIContext()
    private let writerQueue = DispatchQueue(label: "com.adamnolle.3DSeen.landscape-writer")
    private let writerGroup = DispatchGroup()
    private let stateLock = NSLock()

    @Published var frameCount = 0
    @Published var trackingState = "starting"
    @Published var isFinishing = false

    private(set) var captureFolder: URL
    private var lastCapturePosition: SIMD3<Float>?
    private var lastCaptureTime: TimeInterval = 0
    private var nextFrameIndex = 0
    private var acceptsFrames = true
    private var sealed = false
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

    func stop(discardUnsealedCapture: Bool = false) {
        let shouldDiscard = stateLock.withLock { () -> Bool in
            acceptsFrames = false
            return discardUnsealedCapture && !sealed
        }
        session.pause()
        if shouldDiscard {
            writerGroup.notify(queue: writerQueue) { [captureFolder] in
                try? GuidedCaptureTemporarySource.discardIfOwned(captureFolder)
            }
        }
    }

    /// Stops capture and waits for every queued JPEG write before exposing the folder.
    func finish(completion: @escaping (Result<URL, LandscapeCaptureError>) -> Void) {
        guard !isFinishing else { return }
        isFinishing = true
        stateLock.lock()
        acceptsFrames = false
        stateLock.unlock()
        session.pause()
        writerGroup.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.logger.info("Landscape capture finished: \(self.frameCount) frames in \(self.captureFolder.lastPathComponent)")
            self.isFinishing = false
            let hasFrames = CaptureArchiveInspector.containsImageFrames(in: self.captureFolder)
            self.stateLock.withLock { self.sealed = hasFrames }
            guard hasFrames else {
                completion(.failure(.noFramesCaptured))
                return
            }
            completion(.success(self.captureFolder))
        }
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
        let time = frame.timestamp
        let column = frame.camera.transform.columns.3
        let position = SIMD3<Float>(column.x, column.y, column.z)

        stateLock.lock()
        guard acceptsFrames,
              time - lastCaptureTime >= minInterval,
              lastCapturePosition.map({ simd_distance($0, position) >= minTranslation }) ?? true else {
            stateLock.unlock()
            return
        }
        lastCaptureTime = time
        lastCapturePosition = position
        let index = nextFrameIndex
        nextFrameIndex += 1
        writerGroup.enter()
        stateLock.unlock()

        saveFrame(frame.capturedImage, index: index)
    }

    private func saveFrame(_ pixelBuffer: CVPixelBuffer, index: Int) {
        let url = captureFolder.appendingPathComponent(String(format: "frame_%04d.jpg", index))
        let group = writerGroup
        writerQueue.async { [weak self] in
            defer { group.leave() }
            guard let self else { return }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let image = self.ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
            #if canImport(UIKit)
            if let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.92) {
                do {
                    try data.write(to: url, options: .atomic)
                    DispatchQueue.main.async { self.frameCount += 1 }
                } catch {
                    self.logger.error("Could not write landscape frame: \(error.localizedDescription)")
                }
            }
            #endif
        }
    }
}

enum LandscapeCaptureError: LocalizedError {
    case noFramesCaptured

    var errorDescription: String? {
        switch self {
        case .noFramesCaptured:
            return "Landscape Capture did not save any usable camera frames. Retake the scan after AR tracking becomes active."
        }
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
