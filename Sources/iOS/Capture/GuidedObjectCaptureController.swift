import ARKit
import CoreImage
import Foundation
import OSLog
import UIKit

final class GuidedObjectCaptureController: NSObject, ObservableObject, ARSessionDelegate {
    struct FrameCandidate {
        let pixelBuffer: CVPixelBuffer
        let pose: CapturePose
        let orientation: UIInterfaceOrientation
        let trackingIsNormal: Bool
        let quality: FrameQualityMetrics
        let motionIsAcceptable: Bool
    }

    let session = ARSession()
    @Published private(set) var snapshot = GuidedScanSnapshot()

    let detector: ForegroundSubjectDetecting
    let gate: GuidedCaptureGate
    let logger = Logger(subsystem: "com.adamnolle.3DSeen", category: "GuidedObject")
    let analysisQueue = DispatchQueue(label: "com.adamnolle.3DSeen.guided-object.vision", qos: .userInitiated)
    let writerQueue = DispatchQueue(label: "com.adamnolle.3DSeen.guided-object.writer", qos: .userInitiated)
    let writerGroup = DispatchGroup()
    let ciContext = CIContext()
    let lock = NSLock()

    private(set) var captureFolder: URL
    var viewportSize: CGSize = .zero
    var interfaceOrientation: UIInterfaceOrientation = .portrait
    var latestSubject: DetectedSubject?
    var subjectLockTracker = SubjectLockTracker()
    var latestFrame: FrameCandidate?
    var previousObservedPose: CapturePose?
    var lastAcceptedPose: CapturePose?
    var lastDetectionTime: TimeInterval = -.infinity
    var detectionInFlight = false
    var writerBacklog = 0
    var nextFrameIndex = 0
    var sessionGeneration = 0
    var acceptsFrames = false
    var autoCaptureEnabled = true
    var finishing = false
    var sealed = false

    init(
        detector: ForegroundSubjectDetecting = VisionForegroundSubjectDetector(),
        gate: GuidedCaptureGate = GuidedCaptureGate(),
        recommendedFrameCount: Int = 48
    ) {
        self.detector = detector
        self.gate = gate
        captureFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("guided-object-\(UUID().uuidString)", isDirectory: true)
        super.init()
        snapshot.recommendedFrameCount = max(12, recommendedFrameCount)
        session.delegate = self
    }

    func updatePresentation(viewportSize: CGSize, orientation: UIInterfaceOrientation) {
        lock.withLock {
            self.viewportSize = viewportSize
            if orientation != .unknown { self.interfaceOrientation = orientation }
        }
    }

    func start() {
        do {
            try FileManager.default.createDirectory(at: captureFolder, withIntermediateDirectories: true)
        } catch {
            publishFailure("Capture storage could not be prepared: \(error.localizedDescription)")
            return
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = []
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        lock.withLock {
            sessionGeneration += 1
            acceptsFrames = true
            finishing = false
            sealed = false
            subjectLockTracker = SubjectLockTracker()
            latestSubject = nil
            previousObservedPose = nil
            lastAcceptedPose = nil
            lastDetectionTime = -.infinity
            detectionInFlight = false
        }
        publish {
            $0.phase = .seekingSubject
            $0.instruction = "Point at one object and keep it inside the frame."
            $0.isFinishing = false
        }
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop(discardUnsealedCapture: Bool) {
        lock.withLock { acceptsFrames = false }
        session.pause()
        if discardUnsealedCapture && !lock.withLock({ sealed }) {
            writerGroup.notify(queue: writerQueue) { [captureFolder] in
                try? FileManager.default.removeItem(at: captureFolder)
            }
        }
    }

    func retry() {
        start()
    }

    func setAutoCaptureEnabled(_ enabled: Bool) {
        lock.withLock { autoCaptureEnabled = enabled }
        publish { $0.isAutoCaptureEnabled = enabled }
    }

    func captureManually() {
        guard let frame = lock.withLock({ latestFrame }) else { return }
        evaluateAndCapture(frame, manual: true)
    }

    func finish(completion: @escaping (Result<URL, GuidedObjectCaptureError>) -> Void) {
        let shouldFinish = lock.withLock { () -> Bool in
            guard !finishing else { return false }
            finishing = true
            acceptsFrames = false
            return true
        }
        guard shouldFinish else { return }
        session.pause()
        publish {
            $0.phase = .finalizing
            $0.instruction = "Saving the last photos…"
            $0.isFinishing = true
        }
        writerGroup.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let hasFrames = CaptureArchiveInspector.containsImageFrames(in: self.captureFolder)
            self.lock.withLock {
                self.finishing = false
                self.sealed = hasFrames
            }
            self.snapshot.isFinishing = false
            if hasFrames {
                completion(.success(self.captureFolder))
            } else {
                self.snapshot.phase = .failed
                completion(.failure(.noFramesCaptured))
            }
        }
    }

    func publish(_ update: @escaping (inout GuidedScanSnapshot) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            update(&self.snapshot)
        }
    }

    func publishFailure(_ message: String) {
        publish {
            $0.phase = .failed
            $0.instruction = message
        }
    }
}

enum GuidedObjectCaptureError: LocalizedError {
    case noFramesCaptured

    var errorDescription: String? {
        "No usable photos were saved. Keep one object visible, wait for the outline, then move slowly around it."
    }
}

extension NSLock {
    @discardableResult
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
