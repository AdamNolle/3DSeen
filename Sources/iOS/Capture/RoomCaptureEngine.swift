import SwiftUI
import ARKit
import RealityKit
import Combine
import UIKit

/// LiDAR captures measured surface topology while the camera supplies its appearance.
struct RoomCaptureEngine: View {
    @EnvironmentObject var stateMachine: ProcessingStateMachine
    let attemptID: UUID
    @StateObject private var controller = RoomCaptureController()

    var body: some View {
        ZStack {
            RoomSurfaceARView(
                controller: controller,
                surfacePoints: controller.surfacePoints,
                surfacePointRevision: controller.surfacePointRevision,
                objectPoints: controller.objectSurfacePoints,
                objectPointRevision: controller.objectPointRevision
            )
            .ignoresSafeArea()
            LiveCaptureHUD(
                status: LiveCaptureStatus(
                    mode: .space,
                    phase: controller.isProcessing ? .processing : .capturing,
                    frameCount: controller.frameCount,
                    trackingStatus: controller.status,
                    guidanceOverride: controller.captureGuidanceOverride,
                    surfaceTriangleCount: controller.triangleCount,
                    texturedTriangleCount: controller.texturedTriangleCount,
                    textureCoveragePercent: controller.textureCoveragePercent,
                    surfaceClassificationSummary: controller.surfaceClassificationSummary,
                    surfaceSampleCount: controller.surfaceSampleCount,
                    trackedObjectCount: controller.detectedObjectCount,
                    objectSurfaceSampleCount: controller.objectSurfaceSampleCount
                ),
                onFinish: controller.isProcessing ? nil : controller.finish,
                onTextureCapture: controller.isProcessing ? nil : controller.captureTexture,
                textureSnapshotCount: controller.textureCount
            )
        }
        .onAppear {
            controller.onExported = { url in
                stateMachine.send(.finishCapture(scanDataURL: url, attemptID: attemptID))
            }
            controller.onFailure = { message in stateMachine.send(.errorOccurred(message)) }
            controller.start()
        }
        .onDisappear {
            controller.onExported = nil
            controller.onFailure = nil
            controller.cancel()
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.45), trigger: controller.coverageHapticRevision)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.7), trigger: controller.objectDiscoveryHapticRevision)
    }
}

/// All mesh/frame storage is confined to the delegate queue. Cancellation is shared
/// through a lock so an in-flight export cannot publish a discarded capture.
final class RoomCaptureController: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    @Published private(set) var frameCount = 0
    @Published private(set) var textureCount = 0
    @Published private(set) var triangleCount = 0
    @Published private(set) var previewTriangleCount = 0
    @Published private(set) var texturedTriangleCount = 0
    @Published private(set) var surfaceClassificationSummary: String?
    @Published private(set) var surfaceSampleCount = 0
    @Published private(set) var coverageHapticRevision = 0
    @Published private(set) var objectDiscoveryHapticRevision = 0
    @Published private(set) var surfacePoints: [SIMD3<Float>] = []
    @Published private(set) var objectSurfacePoints: [SIMD3<Float>] = []
    private(set) var surfacePointRevision: UInt64 = 0
    private(set) var objectPointRevision: UInt64 = 0
    @Published private(set) var detectedObjectCount: Int?
    @Published private(set) var objectSurfaceSampleCount = 0
    @Published private(set) var isProcessing = false
    @Published private(set) var status = "Starting LiDAR"
    @Published private(set) var captureGuidanceOverride: String?
    var textureCoveragePercent: Int? {
        guard previewTriangleCount > 0 else { return nil }
        return Int((Double(texturedTriangleCount) / Double(previewTriangleCount) * 100).rounded())
    }
    var onExported: ((URL) -> Void)?
    var onFailure: ((String) -> Void)?

    private let queue = DispatchQueue(label: "com.adamnolle.3DSeen.surface-capture", qos: .userInitiated)
    private let previewQueue = DispatchQueue(label: "com.adamnolle.3DSeen.surface-preview", qos: .utility)
    private let objectAnalysisQueue = DispatchQueue(label: "com.adamnolle.3DSeen.object-analysis", qos: .userInitiated)
    private let objectDetector = RoomForegroundObjectDetector()
    private var surfaceCoverage = GuidedSurfaceCoverage(firstHapticThreshold: 240, hapticInterval: 400)
    private var objectCoverage = GuidedSurfaceCoverage(firstHapticThreshold: 64, hapticInterval: 160)
    // Object tracking state is accessed only from objectAnalysisQueue.
    private var objectTracks = RoomObjectTrackRegistry()
    private let lock = NSLock()
    private let context = CIContext()
    private var cancelled = false
    private var requestedTexture = false
    private var accepting = false
    private var sealed = false
    private var started = false
    private var folder: URL?
    private var meshes = BoundedMeshAnchorStore<UUID>()
    private var frames: [LiDARTextureFrame] = []
    private var snapshotCount = 0
    private var lastFrameTime: TimeInterval = 0
    private static let maximumTextureFrameCount = 256
    private var lastCoverageSampleTime: TimeInterval = 0
    private var lastSurfacePublicationTime: TimeInterval = 0
    private var lastSurfacePublicationRevision: UInt64 = 0
    private var hapticScheduler = CaptureHapticScheduler()
    private var trackingMessage = "Starting LiDAR"
    private var trackedObjectCount = 0
    private var objectAnalysisInFlight = false
    private var lastObjectAnalysisTime: TimeInterval = 0
    private var lastObjectPublicationTime: TimeInterval = 0
    private var lastObjectPublicationRevision: UInt64 = 0
    private var lastPublishedRoomObjectCount = -1
    private var lastCameraTransform: simd_float4x4?
    // These preview scheduling values are confined to the AR session delegate queue.
    private var previewBuildInFlight = false
    private var previewDirty = false
    private var lastPreviewBuildTime: TimeInterval = 0
    private var previewRevision: UInt64 = 0
    // RealityKit view and resource state are only accessed on the main queue.
    private weak var previewView: ARView?
    private var previewAnchor: AnchorEntity?
    private var previewRequests = Set<AnyCancellable>()
    private var previewTextures: [URL: TextureResource] = [:]
    private var previewObjectNodes: [Int: Entity] = [:]
    private var installedPreviewRevision: UInt64 = 0

    func registerHapticPulse(_ kind: CaptureHapticKind) {
        switch kind {
        case .surfaceCoverage:
            coverageHapticRevision += 1
        case .objectDiscovery:
            objectDiscoveryHapticRevision += 1
        }
    }

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = queue
    }

    func start() {
        guard !started else { return }
        started = true
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh),
              ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            onFailure?("Detailed space capture requires a LiDAR-equipped iPhone or iPad.")
            return
        }
        lock.withLock { cancelled = false }
        queue.async { [self] in
            guard !isCancelled else { return }
            do {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("space-\(UUID().uuidString)", isDirectory: true)
                for name in [LiDARCaptureBundle.framesName, LiDARCaptureBundle.texturesName] {
                    try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
                }
                folder = root
                accepting = true
                let config = ARWorldTrackingConfiguration()
                let classificationSupported = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
                config.sceneReconstruction = classificationSupported ? .meshWithClassification : .mesh
                // Preserve irregular walls, furniture and surface detail rather than fitting planes.
                config.planeDetection = []
                config.frameSemantics = ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
                    ? [.sceneDepth, .smoothedSceneDepth] : [.sceneDepth]
                session.run(config, options: [.resetTracking, .removeExistingAnchors])
            } catch { fail(error) }
        }
    }

    func captureTexture() {
        guard !isProcessing else { return }
        lock.withLock { requestedTexture = true }
    }

    func finish() {
        guard !isProcessing else { return }
        isProcessing = true
        session.pause()
        queue.async { [self] in
            accepting = false
            session.pause()
            guard !isCancelled, let folder else { return }
            // Drain the serial Vision queue so the last completed masks are attached before export.
            objectAnalysisQueue.async { [self] in
                queue.async { [self] in
                    guard !isCancelled else { return }
                    do {
                        let result = try LiDARTextureExporter.export(
                            meshes: meshes.meshValues, frames: frames,
                            to: folder.appendingPathComponent(LiDARCaptureBundle.modelName),
                            isCancelled: { self.isCancelled }
                        )
                        let report = LiDARCaptureReport(
                            schemaVersion: 3,
                            triangleCount: result.triangleCount,
                            texturedTriangleCount: result.texturedTriangleCount,
                            textureFrameCount: frames.count,
                            textureSnapshotCount: snapshotCount,
                            surfaceCounts: result.surfaceCounts,
                            trackedObjectCount: result.trackedObjectCount
                        )
                        try JSONEncoder().encode(report).write(to: folder.appendingPathComponent(LiDARCaptureBundle.reportName), options: .atomic)
                        try saveCameraMetadata(in: folder)
                        frames.removeAll()
                        meshes.removeAll()
                        DispatchQueue.main.async { [self] in
                            guard !isCancelled else { return }
                            sealed = true
                            isProcessing = false
                            onExported?(folder)
                        }
                    } catch { fail(error) }
                }
            }
        }
    }

    func cancel() {
        lock.withLock { cancelled = true }
        session.pause()
        DispatchQueue.main.async { [weak self] in self?.clearLivePreview() }
        let keep = sealed
        queue.async { [self] in
            accepting = false
            session.pause()
            frames.removeAll()
            meshes.removeAll()
            if !keep, let folder { try? GuidedCaptureTemporarySource.discardIfOwned(folder) }
        }
    }

    private var isCancelled: Bool { lock.withLock { cancelled } }

    private static func classificationSummary(for classificationCounts: [UInt8: Int]) -> String? {
        var counts: [String: Int] = [:]
        for (rawValue, count) in classificationCounts where rawValue != 0 {
            counts[LiDARSurfaceClassification.label(for: rawValue), default: 0] += count
        }
        let labels = counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }.prefix(3).map(\.key)
        return labels.isEmpty ? nil : labels.joined(separator: " · ")
    }

    private func fail(_ error: Error) {
        accepting = false
        session.pause()
        if let folder { try? GuidedCaptureTemporarySource.discardIfOwned(folder) }
        frames.removeAll()
        meshes.removeAll()
        DispatchQueue.main.async { [self] in
            guard !isCancelled else { return }
            isProcessing = false
            onFailure?(error.localizedDescription)
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { update(anchors) }
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { update(anchors) }
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        guard accepting, !isCancelled else { return }
        for anchor in anchors { meshes.remove(anchor.identifier) }
        publishMeshState()
        scheduleLivePreview()
    }

    private func update(_ anchors: [ARAnchor]) {
        guard accepting, !isCancelled else { return }
        for anchor in anchors.compactMap({ $0 as? ARMeshAnchor }) where anchor.geometry.faces.count >= 1 {
            guard meshes.canAcceptUpdate(triangleCount: anchor.geometry.faces.count, for: anchor.identifier) else {
                break
            }
            do {
                let mesh = try LiDARCaptureFrames.mesh(anchor)
                guard meshes.update(mesh, for: anchor.identifier) else {
                    break
                }
            } catch {
                fail(error)
                return
            }
        }
        publishMeshState()
        scheduleLivePreview()
    }

    private func publishMeshState() {
        let count = meshes.triangleCount
        let classificationSummary = Self.classificationSummary(for: meshes.classificationCounts)
        let guidance = captureGuidanceOverrideText
        publish {
            $0.triangleCount = count
            $0.surfaceClassificationSummary = classificationSummary
            $0.captureGuidanceOverride = guidance
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let message: String
        switch camera.trackingState {
        case .normal: message = "Tracking surfaces"
        case .limited: message = "Move slowly · tracking limited"
        case .notAvailable: message = "Waiting for tracking"
        }
        trackingMessage = message
        let statusMessage = trackingStatus
        publish { $0.status = statusMessage }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        guard accepting, !isCancelled else { return }
        fail(error)
    }
    func sessionWasInterrupted(_ session: ARSession) {
        guard accepting, !isCancelled else { return }
        fail(NSError(domain: "LiDARCapture", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "Space capture was interrupted. Retake this section to keep its geometry and textures aligned."]))
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard accepting, !isCancelled, let folder, case .normal = frame.camera.trackingState else { return }
        do {
            updateSurfaceCoverage(from: frame)
            let takeTexture = lock.withLock { () -> Bool in
                let value = requestedTexture
                requestedTexture = false
                return value
            }
            if takeTexture {
                try LiDARCaptureFrames.saveTexture(
                    frame,
                    index: snapshotCount,
                    folder: folder.appendingPathComponent(LiDARCaptureBundle.texturesName),
                    context: context
                )
                snapshotCount += 1
                let count = snapshotCount
                publish { $0.textureCount = count }
            }
            let textureFrame = try saveTextureFrameIfNeeded(from: frame, folder: folder)
            scheduleObjectAnalysis(from: frame, textureFrame: textureFrame)
        } catch {
            fail(error)
        }
    }

    private func saveTextureFrameIfNeeded(from frame: ARFrame, folder: URL) throws -> LiDARTextureFrame? {
        guard frame.timestamp - lastFrameTime >= 0.4,
              frames.count < Self.maximumTextureFrameCount else { return nil }
        if let last = lastCameraTransform {
            let translation = simd_distance(last.columns.3, frame.camera.transform.columns.3)
            let facing = simd_dot(last.columns.2, frame.camera.transform.columns.2)
            guard translation >= 0.12 || facing < 0.978 else { return nil }
        }
        guard frame.smoothedSceneDepth != nil || frame.sceneDepth != nil else { return nil }
        let saved = try LiDARCaptureFrames.save(
            frame,
            index: frames.count,
            folder: folder.appendingPathComponent(LiDARCaptureBundle.framesName),
            context: context
        )
        frames.append(saved)
        scheduleLivePreview()
        lastFrameTime = frame.timestamp
        lastCameraTransform = frame.camera.transform
        let count = frames.count
        let guidance = captureGuidanceOverrideText
        publish {
            $0.frameCount = count
            if count == Self.maximumTextureFrameCount { $0.status = "Photo limit reached · finish section" }
            $0.captureGuidanceOverride = guidance
        }
        return saved
    }

    private var captureGuidanceOverrideText: String? {
        if meshes.didReachLimit {
            return "Mesh limit reached · finish this section to save the captured surfaces."
        }
        if frames.count >= Self.maximumTextureFrameCount {
            return "Texture-frame limit reached · finish this section before scanning another area."
        }
        if surfaceCoverage.isAtSampleLimit || objectCoverage.isAtSampleLimit {
            return "Dot coverage limit reached · finish this section to save its scan data."
        }
        return nil
    }

    private func updateSurfaceCoverage(from frame: ARFrame) {
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }
        guard frame.timestamp - lastCoverageSampleTime >= 0.16,
              CVPixelBufferGetPixelFormatType(depthData.depthMap) == kCVPixelFormatType_DepthFloat32
        else { return }
        let depthMap = depthData.depthMap
        lastCoverageSampleTime = frame.timestamp

        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        guard depthWidth > 0, depthHeight > 0, depthWidth <= Int.max / depthHeight else { return }
        let depthCount = depthWidth * depthHeight
        guard CVPixelBufferLockBaseAddress(depthMap, .readOnly) == kCVReturnSuccess else { return }
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            return
        }
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let rowBytes = CVPixelBufferGetBytesPerRow(depthMap)
        let sourceRowLength = rowBytes / MemoryLayout<Float>.stride
        var depths = [Float](repeating: 0, count: depthCount)
        for row in 0..<depthHeight {
            let source = baseAddress
                .advanced(by: row * rowBytes)
                .assumingMemoryBound(to: Float.self)
            let destinationOffset = row * depthWidth
            for column in 0..<depthWidth {
                guard column < sourceRowLength else { break }
                depths[destinationOffset + column] = source[column]
            }
        }

        let intrinsics = frame.camera.intrinsics
        let imageWidth = CVPixelBufferGetWidth(frame.capturedImage)
        let imageHeight = CVPixelBufferGetHeight(frame.capturedImage)
        let confidenceValues = Self.confidenceValues(
            from: depthData.confidenceMap,
            width: depthWidth,
            height: depthHeight
        )
        let points = GuidedDepthProjection.sampledWorldPositions(
            depths: depths,
            confidenceValues: confidenceValues,
            configuration: GuidedDepthProjection.GridConfiguration(
                depthSize: SIMD2<Int>(depthWidth, depthHeight),
                imageSize: SIMD2<Int>(imageWidth, imageHeight),
                sampleStep: max(8, depthWidth / 24),
                focalLength: SIMD2<Float>(intrinsics.columns.0.x, intrinsics.columns.1.y),
                principalPoint: SIMD2<Float>(intrinsics.columns.2.x, intrinsics.columns.2.y),
                cameraTransform: frame.camera.transform,
                minimumConfidence: UInt8(ARConfidenceLevel.medium.rawValue)
            )
        )
        guard !points.isEmpty else { return }

        _ = surfaceCoverage.insert(points)
        let shouldPublish = frame.timestamp - lastSurfacePublicationTime >= 0.35
        let publishedPoints = shouldPublish
            && surfaceCoverage.displayRevision != lastSurfacePublicationRevision
            ? surfaceCoverage.points
            : nil
        let sampleCount = shouldPublish ? surfaceCoverage.uniqueSurfaceCellCount : nil
        if shouldPublish {
            lastSurfacePublicationTime = frame.timestamp
            if publishedPoints != nil {
                lastSurfacePublicationRevision = surfaceCoverage.displayRevision
            }
        }

        let hapticPulse = hapticScheduler.nextPulse(
            at: frame.timestamp,
            coverageMilestone: surfaceCoverage.hapticMilestone + objectCoverage.hapticMilestone
        )
        guard sampleCount != nil || publishedPoints != nil || hapticPulse != nil else { return }

        publish { controller in
            if let sampleCount { controller.surfaceSampleCount = sampleCount }
            if let publishedPoints {
                controller.surfacePoints = publishedPoints
                controller.surfacePointRevision &+= 1
            }
            if let hapticPulse { controller.registerHapticPulse(hapticPulse) }
            controller.captureGuidanceOverride = self.captureGuidanceOverrideText
        }
    }

    private func scheduleObjectAnalysis(from frame: ARFrame, textureFrame: LiDARTextureFrame?) {
        guard !objectAnalysisInFlight, frame.timestamp - lastObjectAnalysisTime >= 0.9 else { return }
        objectAnalysisInFlight = true
        lastObjectAnalysisTime = frame.timestamp
        let timestamp = frame.timestamp
        objectAnalysisQueue.async { [weak self] in
            guard let self else { return }
            let detection = try? objectDetector.detect(in: frame)
            let observations = detection?.observations ?? []
            let objects = objectTracks.update(observations: observations, timestamp: timestamp)
            let objectCount = objectTracks.count
            let points = objects.flatMap(\.points)
            let identifiersByLabel = Dictionary(uniqueKeysWithValues: objects.map {
                ($0.instanceLabel, $0.identifier)
            })
            let objectMask = detection?.instanceMask.mapping(identifiersByLabel)
            queue.async { [weak self] in
                guard let self else { return }
                objectAnalysisInFlight = false
                guard !isCancelled else { return }
                if let textureFrame, let objectMask, !identifiersByLabel.isEmpty,
                   let index = frames.firstIndex(where: { $0.imageURL == textureFrame.imageURL }) {
                    frames[index] = frames[index].attaching(objectMask)
                }
                guard accepting else { return }
                publishObjectCoverage(points: points, objectCount: objectCount, timestamp: timestamp)
            }
        }
    }

    private func publishObjectCoverage(points: [SIMD3<Float>], objectCount: Int, timestamp: TimeInterval) {
        _ = objectCoverage.insert(points)
        trackedObjectCount = objectCount
        let shouldPublish = timestamp - lastObjectPublicationTime >= 0.35
        let publishedPoints = shouldPublish && objectCoverage.displayRevision != lastObjectPublicationRevision
            ? objectCoverage.points : nil
        let sampleCount = shouldPublish ? objectCoverage.uniqueSurfaceCellCount : nil
        if shouldPublish {
            lastObjectPublicationTime = timestamp
            if publishedPoints != nil { lastObjectPublicationRevision = objectCoverage.displayRevision }
        }
        let objectCountChanged = trackedObjectCount != lastPublishedRoomObjectCount
        let objectWasDiscovered = objectCount > max(0, lastPublishedRoomObjectCount)
        let hapticPulse = hapticScheduler.nextPulse(
            at: timestamp,
            coverageMilestone: surfaceCoverage.hapticMilestone + objectCoverage.hapticMilestone,
            objectWasDiscovered: objectWasDiscovered
        )
        guard sampleCount != nil || publishedPoints != nil || hapticPulse != nil || objectCountChanged else { return }
        lastPublishedRoomObjectCount = trackedObjectCount
        let statusMessage = trackingStatus

        publish { controller in
            if let sampleCount { controller.objectSurfaceSampleCount = sampleCount }
            if let publishedPoints {
                controller.objectSurfacePoints = publishedPoints
                controller.objectPointRevision &+= 1
            }
            controller.detectedObjectCount = objectCount
            controller.status = statusMessage
            if let hapticPulse { controller.registerHapticPulse(hapticPulse) }
            controller.captureGuidanceOverride = self.captureGuidanceOverrideText
        }
    }

    private var trackingStatus: String {
        trackingMessage
    }

    private static func confidenceValues(from confidenceMap: CVPixelBuffer?, width: Int, height: Int) -> [UInt8]? {
        guard let confidenceMap,
              width > 0, height > 0, width <= Int.max / height,
              CVPixelBufferGetPixelFormatType(confidenceMap) == kCVPixelFormatType_OneComponent8,
              CVPixelBufferGetWidth(confidenceMap) == width,
              CVPixelBufferGetHeight(confidenceMap) == height,
              CVPixelBufferLockBaseAddress(confidenceMap, .readOnly) == kCVReturnSuccess
        else { return nil }
        guard let baseAddress = CVPixelBufferGetBaseAddress(confidenceMap) else {
            CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }

        let rowBytes = CVPixelBufferGetBytesPerRow(confidenceMap)
        var values = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let source = baseAddress.advanced(by: row * rowBytes).assumingMemoryBound(to: UInt8.self)
            let destinationOffset = row * width
            for column in 0..<width {
                values[destinationOffset + column] = source[column]
            }
        }
        return values
    }

    private func publish(_ update: @escaping (RoomCaptureController) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isCancelled, !self.isProcessing else { return }
            update(self)
        }
    }

    private func saveCameraMetadata(in folder: URL) throws {
        let metadata: [[String: Any]] = frames.map { frame in
            let transform = frame.camera.worldToCamera.inverse
            let intrinsics = frame.camera.intrinsics
            return ["image": frame.imageURL.lastPathComponent, "depth": frame.imageURL.lastPathComponent + ".depth.f32",
                    "cameraToWorldColumnMajor": (0..<4).flatMap { column in (0..<4).map { transform[column][$0] } },
                    "intrinsicsColumnMajor": (0..<3).flatMap { column in (0..<3).map { intrinsics[column][$0] } },
                    "imageWidth": frame.camera.imageWidth, "imageHeight": frame.camera.imageHeight,
                    "depthWidth": frame.camera.depthWidth, "depthHeight": frame.camera.depthHeight]
        }
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "units": "meters",
                                                               "depthEncoding": "little-endian-float32", "frames": metadata], options: [.sortedKeys])
        try data.write(to: folder.appendingPathComponent(LiDARCaptureBundle.framesName).appendingPathComponent("cameras.json"), options: .atomic)
    }
}

extension RoomCaptureController {
    @MainActor
    func attachPreview(_ view: ARView) {
        previewView = view
        session.delegateQueue = queue
        session.delegate = self
    }

    /// Builds the RealityKit mesh away from the session and UI queues. Coalescing keeps
    /// fast ARMeshAnchor updates from creating a queue of stale, expensive previews.
    private func scheduleLivePreview() {
        guard accepting, !isCancelled else { return }
        previewDirty = true
        guard !previewBuildInFlight, !meshes.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPreviewBuildTime >= 1.25 else { return }
        previewBuildInFlight = true
        previewDirty = false
        lastPreviewBuildTime = now
        previewRevision &+= 1
        let revision = previewRevision
        let meshSnapshot = meshes.meshValues
        let frameSnapshot = frames
        previewQueue.async { [weak self] in
            let preview = LiveMeshPreviewBuilder.build(
                meshes: meshSnapshot,
                frames: frameSnapshot,
                revision: revision,
                isCancelled: { self?.isCancelled ?? true }
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let preview, !self.isCancelled {
                    self.installLivePreview(preview)
                    self.previewTriangleCount = preview.sampledTriangleCount
                    self.texturedTriangleCount = preview.texturedTriangleCount
                }
                self.queue.async {
                    self.previewBuildInFlight = false
                    if self.previewDirty { self.scheduleLivePreview() }
                }
            }
        }
    }

    @MainActor
    private func installLivePreview(_ preview: LiveMeshPreview) {
        guard preview.revision >= installedPreviewRevision, !isCancelled, let previewView else { return }
        installedPreviewRevision = preview.revision
        previewRequests.removeAll()
        previewTextures = previewTextures.filter { preview.textureURLs.contains($0.key) }
        if let previewAnchor { previewView.scene.anchors.remove(previewAnchor) }
        let anchor = AnchorEntity(world: .zero)
        previewView.scene.anchors.append(anchor)
        previewAnchor = anchor
        previewObjectNodes.removeAll()

        for batch in preview.batches {
            var descriptor = MeshDescriptor(name: "LiveSurface")
            descriptor.positions = MeshBuffers.Positions(batch.positions)
            descriptor.normals = MeshBuffers.Normals(batch.normals)
            descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(batch.textureCoordinates)
            descriptor.primitives = .triangles(batch.indices)
            MeshResource.generateAsync(from: [descriptor])
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { [weak self, weak anchor] mesh in
                        guard let self, let anchor, self.installedPreviewRevision == preview.revision,
                              !self.isCancelled else { return }
                        let entity = ModelEntity(
                            mesh: mesh,
                            materials: [CapturePreviewMaterials.blueprintSurface()]
                        )
                        if let objectIdentifier = batch.objectIdentifier {
                            let objectNode = self.previewObjectNodes[objectIdentifier] ?? {
                                let node = Entity()
                                node.name = "LiveObject_\(objectIdentifier)"
                                anchor.addChild(node)
                                self.previewObjectNodes[objectIdentifier] = node
                                return node
                            }()
                            entity.name = "LiveObjectSurface_\(objectIdentifier)"
                            objectNode.addChild(entity)
                        } else {
                            entity.name = "LiveRoomSurface"
                            anchor.addChild(entity)
                        }
                        guard let textureURL = batch.textureURL else { return }
                        if let cached = self.previewTextures[textureURL] {
                            entity.model?.materials = [Self.texturedMeshMaterial(cached)]
                            return
                        }
                        TextureResource.loadAsync(contentsOf: textureURL, withName: "surface-\(preview.revision)-\(textureURL.lastPathComponent)")
                            .receive(on: DispatchQueue.main)
                            .sink(
                                receiveCompletion: { _ in },
                                receiveValue: { [weak self, weak entity] texture in
                                    guard let self, let entity,
                                          self.installedPreviewRevision == preview.revision,
                                          !self.isCancelled else { return }
                                    self.previewTextures[textureURL] = texture
                                    entity.model?.materials = [Self.texturedMeshMaterial(texture)]
                                }
                            )
                            .store(in: &self.previewRequests)
                    }
                )
                .store(in: &previewRequests)
        }
    }

    @MainActor
    private func clearLivePreview() {
        previewRequests.removeAll()
        previewTextures.removeAll()
        previewObjectNodes.removeAll()
        installedPreviewRevision &+= 1
        if let previewAnchor, let previewView { previewView.scene.anchors.remove(previewAnchor) }
        previewAnchor = nil
        texturedTriangleCount = 0
        previewTriangleCount = 0
    }

    private static func texturedMeshMaterial(_ texture: TextureResource) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .white, texture: .init(texture))
        material.roughness = 0.85
        material.faceCulling = .none
        return material
    }
}
