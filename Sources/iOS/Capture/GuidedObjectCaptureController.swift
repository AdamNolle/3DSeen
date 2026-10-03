import ARKit
import CoreImage
import Foundation
import OSLog
import UIKit

final class GuidedObjectCaptureController: NSObject, ObservableObject, ARSessionDelegate {
    struct CoverageFramePublication {
        let shouldPublish: Bool
        let count: Int
        let hapticPulseRevision: Int
        let isAtSampleLimit: Bool
        let points: [SIMD3<Float>]?
    }

    struct FrameCandidate {
        let frame: ARFrame
        let pixelBuffer: CVPixelBuffer
        let pose: CapturePose
        let orientation: UIInterfaceOrientation
        let sessionGeneration: Int
        let surfaceMask: LiDARSurfaceMask?
        let trackingIsNormal: Bool
        let quality: FrameQualityMetrics
        let motionIsAcceptable: Bool
    }

    struct FramePresentation {
        let viewportSize: CGSize
        let orientation: UIInterfaceOrientation
        let acceptsFrames: Bool
        let sessionGeneration: Int
    }

    let session = ARSession()
    @Published private(set) var snapshot = GuidedScanSnapshot()
    @Published private(set) var liveMeshPreview: LiveMeshPreview?
    @Published private(set) var meshTriangleCount = 0
    @Published private(set) var texturedMeshTriangleCount = 0

    let detector: ForegroundSubjectDetecting
    let gate: GuidedCaptureGate
    let logger = Logger(subsystem: "com.adamnolle.3DSeen", category: "GuidedObject")
    let frameProcessingQueue = DispatchQueue(
        label: "com.adamnolle.3DSeen.guided-object.frames",
        qos: .userInitiated
    )
    let previewQueue = DispatchQueue(label: "com.adamnolle.3DSeen.guided-object.preview", qos: .utility)
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
    var surfaceCoverage = GuidedSurfaceCoverage()
    var hapticScheduler = CaptureHapticScheduler()
    var coverageHapticPulseRevision = 0
    var snapshotPublicationGate = GuidedSnapshotPublicationGate()
    var lastPublishedSurfaceRevision: UInt64 = 0
    var lastSurfacePublicationTime: TimeInterval = -.infinity
    var writerBacklog = 0
    var nextFrameIndex = 0
    var sessionGeneration = 0
    var acceptsFrames = false
    var autoCaptureEnabled = true
    var finishing = false
    var sealed = false
    // AR mesh anchors, texture frames, and preview scheduling are queue-confined.
    var surfaceMeshes = BoundedMeshAnchorStore<UUID>()
    var textureFrames: [LiDARTextureFrame] = []
    var previewBuildInFlight = false
    var previewDirty = false
    var lastPreviewBuildTime: TimeInterval = 0
    var previewRevision: UInt64 = 0
    var meshCaptureDisabled = false
    private var publishedLiveMeshPreviewRevision: UInt64 = 0

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
        session.delegateQueue = frameProcessingQueue
        session.delegate = self
    }

    func updatePresentation(viewportSize: CGSize, orientation: UIInterfaceOrientation) {
        lock.withLock {
            self.viewportSize = viewportSize
            if orientation != .unknown { self.interfaceOrientation = orientation }
        }
    }

    func start() {
        let previousCapture = lock.withLock { () -> (URL, Bool) in
            acceptsFrames = false
            return (captureFolder, sealed)
        }
        let newCaptureFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("guided-object-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: newCaptureFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: newCaptureFolder.appendingPathComponent("surface-frames", isDirectory: true),
                withIntermediateDirectories: true
            )
        } catch {
            try? FileManager.default.removeItem(at: newCaptureFolder)
            publishFailure("Capture storage could not be prepared: \(error.localizedDescription)")
            return
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = []
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        lock.withLock {
            captureFolder = newCaptureFolder
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
            latestFrame = nil
            nextFrameIndex = 0
            surfaceCoverage.reset()
            hapticScheduler = CaptureHapticScheduler()
            coverageHapticPulseRevision = 0
            snapshotPublicationGate.reset()
            lastPublishedSurfaceRevision = 0
            lastSurfacePublicationTime = -.infinity
        }
        if !previousCapture.1 {
            writerGroup.notify(queue: writerQueue) {
                try? FileManager.default.removeItem(at: previousCapture.0)
            }
        }
        let resetPreviewRevision = frameProcessingQueue.sync { () -> UInt64 in
            surfaceMeshes.removeAll(keepingCapacity: false)
            textureFrames.removeAll(keepingCapacity: false)
            previewBuildInFlight = false
            previewDirty = false
            lastPreviewBuildTime = 0
            previewRevision &+= 1
            meshCaptureDisabled = false
            return previewRevision
        }
        publish {
            $0.phase = .seekingSubject
            $0.instruction = "Point at one object and keep it inside the frame."
            $0.frameCount = 0
            $0.points = []
            $0.surfacePoints = []
            $0.surfacePointRevision &+= 1
            $0.surfacePointCount = 0
            $0.coverageHapticPulseRevision = 0
            $0.surfaceCoverageLimitReached = false
            $0.isFinishing = false
        }
        DispatchQueue.main.async { [weak self] in
            self?.publishLiveMeshPreview(nil, revision: resetPreviewRevision)
            self?.meshTriangleCount = 0
        }
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop(discardUnsealedCapture: Bool) {
        lock.withLock { acceptsFrames = false }
        session.pause()
        let folderToDiscard = lock.withLock { () -> URL? in
            guard discardUnsealedCapture, !sealed else { return nil }
            return captureFolder
        }
        if let folderToDiscard {
            writerGroup.notify(queue: writerQueue) {
                try? FileManager.default.removeItem(at: folderToDiscard)
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
        let folder = lock.withLock { () -> URL? in
            guard !finishing else { return nil }
            finishing = true
            acceptsFrames = false
            return captureFolder
        }
        guard let folder else { return }
        session.pause()
        publish {
            $0.phase = .finalizing
            $0.instruction = "Finishing the live object mesh…"
            $0.isFinishing = true
        }
        frameProcessingQueue.async { [weak self] in
            guard let self else { return }
            let meshSnapshot = self.surfaceMeshes.meshValues
            self.writerGroup.notify(queue: self.writerQueue) { [weak self] in
                guard let self else { return }
                let textureSnapshot = self.frameProcessingQueue.sync { self.textureFrames }
            let exported = self.finalizeObjectBundle(meshes: meshSnapshot, frames: textureSnapshot, in: folder)
                DispatchQueue.main.async {
                let hasFrames = CaptureArchiveInspector.containsImageFrames(in: folder)
                    self.lock.withLock {
                        self.finishing = false
                        self.sealed = hasFrames
                    }
                    self.snapshot.isFinishing = false
                    guard hasFrames else {
                        self.snapshot.phase = .failed
                        completion(.failure(.noFramesCaptured))
                        return
                    }
                    if exported {
                        self.snapshot.instruction = "Object mesh saved with \(textureSnapshot.count) depth-aligned texture views."
                    } else if !meshSnapshot.isEmpty {
                        self.snapshot.instruction = "Kept the photo scan; add more object views for a textured mesh next time."
                    }
                completion(.success(folder))
                }
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

    func publishLiveMeshPreview(_ preview: LiveMeshPreview?, revision: UInt64) {
        DispatchQueue.main.async { [weak self] in
            guard let self, revision >= self.publishedLiveMeshPreviewRevision else { return }
            self.publishedLiveMeshPreviewRevision = revision
            self.liveMeshPreview = preview
            self.texturedMeshTriangleCount = preview?.texturedTriangleCount ?? 0
        }
    }

    func publishMeshTriangleCount(_ count: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.meshTriangleCount = count
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
