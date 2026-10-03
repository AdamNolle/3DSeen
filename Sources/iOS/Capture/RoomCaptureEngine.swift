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
            RoomSurfaceARView(controller: controller, surfacePoints: controller.surfacePoints)
                .ignoresSafeArea()
            LiveCaptureHUD(
                status: LiveCaptureStatus(mode: .space, phase: controller.isProcessing ? .processing : .capturing,
                                          frameCount: controller.frameCount, trackingStatus: controller.status,
                                          surfaceTriangleCount: controller.triangleCount,
                texturedTriangleCount: controller.texturedTriangleCount,
                textureCoveragePercent: controller.textureCoveragePercent,
                surfaceClassificationSummary: controller.surfaceClassificationSummary,
                surfaceSampleCount: controller.surfaceSampleCount),
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
        .sensoryFeedback(
            .impact(weight: .light, intensity: 0.55),
            trigger: controller.coverageHapticMilestone
        )
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
    @Published private(set) var coverageHapticMilestone = 0
    @Published private(set) var surfacePoints: [SIMD3<Float>] = []
    @Published private(set) var isProcessing = false
    @Published private(set) var status = "Starting LiDAR"
    var textureCoveragePercent: Int? {
        guard previewTriangleCount > 0 else { return nil }
        return Int((Double(texturedTriangleCount) / Double(previewTriangleCount) * 100).rounded())
    }
    var onExported: ((URL) -> Void)?
    var onFailure: ((String) -> Void)?

    private let queue = DispatchQueue(label: "com.adamnolle.3DSeen.surface-capture", qos: .userInitiated)
    private let previewQueue = DispatchQueue(label: "com.adamnolle.3DSeen.surface-preview", qos: .utility)
    private var surfaceCoverage = GuidedSurfaceCoverage(firstHapticThreshold: 240, hapticInterval: 400)
    private let lock = NSLock()
    private let context = CIContext()
    private var cancelled = false
    private var requestedTexture = false
    private var accepting = false
    private var sealed = false
    private var started = false
    private var folder: URL?
    private var meshes: [UUID: LiDARSurfaceMesh] = [:]
    private var frames: [LiDARTextureFrame] = []
    private var snapshotCount = 0
    private var lastFrameTime: TimeInterval = 0
    private var lastCoverageSampleTime: TimeInterval = 0
    private var lastSurfacePublicationTime: TimeInterval = 0
    private var lastSurfacePublicationRevision: UInt64 = 0
    private var lastHapticTimestamp: TimeInterval = 0
    private var lastPublishedHapticMilestone = 0
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
    private var installedPreviewRevision: UInt64 = 0

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
            do {
                let result = try LiDARTextureExporter.export(
                    meshes: Array(meshes.values), frames: frames,
                    to: folder.appendingPathComponent(LiDARCaptureBundle.modelName),
                    isCancelled: { self.isCancelled }
                )
                let report = LiDARCaptureReport(schemaVersion: 2, triangleCount: result.triangleCount,
                                                texturedTriangleCount: result.texturedTriangleCount,
                                                textureFrameCount: frames.count, textureSnapshotCount: snapshotCount,
                                                surfaceCounts: result.surfaceCounts)
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

    private static func classificationSummary(for meshes: Dictionary<UUID, LiDARSurfaceMesh>.Values) -> String? {
        var counts: [String: Int] = [:]
        for mesh in meshes where !mesh.classifications.isEmpty {
            for rawValue in mesh.classifications where rawValue != 0 {
                counts[LiDARSurfaceClassification.label(for: rawValue), default: 0] += 1
            }
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
        for anchor in anchors { meshes[anchor.identifier] = nil }
        scheduleLivePreview()
    }

    private func update(_ anchors: [ARAnchor]) {
        guard accepting, !isCancelled else { return }
        do {
            for anchor in anchors.compactMap({ $0 as? ARMeshAnchor }) where anchor.geometry.faces.count >= 1 {
                meshes[anchor.identifier] = try LiDARCaptureFrames.mesh(anchor)
            }
            guard meshes.values.reduce(0, { $0 + $1.triangleCount }) <= 500_000 else { throw LiDARSurfaceError.tooLarge }
            let count = meshes.values.reduce(0, { $0 + $1.triangleCount })
            let classificationSummary = Self.classificationSummary(for: meshes.values)
            publish {
                $0.triangleCount = count
                $0.surfaceClassificationSummary = classificationSummary
            }
            scheduleLivePreview()
        } catch { fail(error) }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let message: String
        switch camera.trackingState {
        case .normal: message = "Tracking surfaces"
        case .limited: message = "Move slowly · tracking limited"
        case .notAvailable: message = "Waiting for tracking"
        }
        publish { $0.status = message }
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
                try LiDARCaptureFrames.saveTexture(frame, index: snapshotCount,
                                                  folder: folder.appendingPathComponent(LiDARCaptureBundle.texturesName), context: context)
                snapshotCount += 1
                let count = snapshotCount
                publish { $0.textureCount = count }
            }
            guard frame.timestamp - lastFrameTime >= 0.4, frames.count < 256 else { return }
            if let last = lastCameraTransform {
                let translation = simd_distance(last.columns.3, frame.camera.transform.columns.3)
                let facing = simd_dot(last.columns.2, frame.camera.transform.columns.2)
                guard translation >= 0.12 || facing < 0.978 else { return }
            }
            guard frame.smoothedSceneDepth != nil || frame.sceneDepth != nil else { return }
            let saved = try LiDARCaptureFrames.save(frame, index: frames.count,
                                                   folder: folder.appendingPathComponent(LiDARCaptureBundle.framesName), context: context)
            frames.append(saved)
            lastFrameTime = frame.timestamp
            lastCameraTransform = frame.camera.transform
            let count = frames.count
            publish {
                $0.frameCount = count
                if count == 256 { $0.status = "Photo limit reached · finish this section" }
            }
            scheduleLivePreview()
        } catch { fail(error) }
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

        let milestone: Int?
        if surfaceCoverage.hapticMilestone > lastPublishedHapticMilestone,
           frame.timestamp - lastHapticTimestamp >= 1.1 {
            milestone = surfaceCoverage.hapticMilestone
            lastPublishedHapticMilestone = surfaceCoverage.hapticMilestone
            lastHapticTimestamp = frame.timestamp
        } else {
            milestone = nil
        }
        guard sampleCount != nil || publishedPoints != nil || milestone != nil else { return }

        publish { controller in
            if let sampleCount { controller.surfaceSampleCount = sampleCount }
            if let publishedPoints { controller.surfacePoints = publishedPoints }
            if let milestone { controller.coverageHapticMilestone = milestone }
        }
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
        let meshSnapshot = Array(meshes.values)
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
                        let entity = ModelEntity(mesh: mesh, materials: [Self.blueprintMeshMaterial()])
                        anchor.addChild(entity)
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
        installedPreviewRevision &+= 1
        if let previewAnchor, let previewView { previewView.scene.anchors.remove(previewAnchor) }
        previewAnchor = nil
        texturedTriangleCount = 0
        previewTriangleCount = 0
    }

    private static func blueprintMeshMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.09, green: 0.31, blue: 0.92, alpha: 1), texture: nil)
        material.roughness = 0.85
        material.faceCulling = .none
        material.blending = .transparent(opacity: 0.42)
        return material
    }

    private static func texturedMeshMaterial(_ texture: TextureResource) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .white, texture: .init(texture))
        material.roughness = 0.85
        material.faceCulling = .none
        return material
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

struct RoomSurfaceARView: UIViewRepresentable {
    let controller: RoomCaptureController
    let surfacePoints: [SIMD3<Float>]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = controller.session
        controller.attachPreview(view)
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.update(points: surfacePoints)
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.detach(from: uiView)
    }

    @MainActor
    final class Coordinator {
        private let anchor = AnchorEntity(world: .zero)
        private let dotEntity = ModelEntity()
        private let dotMaterial = UnlitMaterial(color: UIColor(red: 0.20, green: 0.72, blue: 1, alpha: 1))
        private let dotBuildQueue = DispatchQueue(label: "com.adamnolle.3DSeen.room-surface-dots", qos: .userInitiated)
        private weak var view: ARView?
        private var meshRequests = Set<AnyCancellable>()
        private var revision: UInt64 = 0
        private var previousPoints: [SIMD3<Float>] = []
        private var pendingPoints: [SIMD3<Float>]?
        private var buildInFlight = false

        func attach(to view: ARView) {
            self.view = view
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                view.environment.sceneUnderstanding.options.insert(.occlusion)
            }
            if !view.scene.anchors.contains(where: { $0 === anchor }) {
                view.scene.addAnchor(anchor)
            }
            if !anchor.children.contains(where: { $0 === dotEntity }) {
                anchor.addChild(dotEntity)
            }
        }

        func update(points: [SIMD3<Float>]) {
            guard points != previousPoints else { return }
            previousPoints = points
            revision &+= 1
            guard !points.isEmpty else {
                pendingPoints = nil
                meshRequests.removeAll()
                dotEntity.model = nil
                return
            }
            pendingPoints = points
            scheduleDotMeshBuildIfNeeded()
        }

        func detach(from view: ARView) {
            meshRequests.removeAll()
            pendingPoints = nil
            revision &+= 1
            view.scene.anchors.remove(anchor)
            self.view = nil
        }

        private func scheduleDotMeshBuildIfNeeded() {
            guard !buildInFlight, let points = pendingPoints else { return }
            pendingPoints = nil
            buildInFlight = true
            let buildRevision = revision
            dotBuildQueue.async { [weak self] in
                let geometry = GuidedSurfaceDotMesh.build(points: points)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.buildInFlight = false
                    if self.revision == buildRevision, self.view != nil {
                        self.installDotMesh(geometry, revision: buildRevision)
                    }
                    self.scheduleDotMeshBuildIfNeeded()
                }
            }
        }

        private func installDotMesh(_ geometry: GuidedSurfaceDotMesh, revision: UInt64) {
            meshRequests.removeAll()
            guard !geometry.positions.isEmpty else {
                dotEntity.model = nil
                return
            }
            var descriptor = MeshDescriptor(name: "GuidedRoomSurfaceDots")
            descriptor.positions = MeshBuffers.Positions(geometry.positions)
            descriptor.normals = MeshBuffers.Normals(geometry.normals)
            descriptor.primitives = .triangles(geometry.triangleIndices)
            MeshResource.generateAsync(from: [descriptor])
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { [weak self] mesh in
                        guard let self, self.revision == revision, self.view != nil else { return }
                        self.dotEntity.model = ModelComponent(mesh: mesh, materials: [self.dotMaterial])
                    }
                )
                .store(in: &meshRequests)
        }
    }
}

struct LiveMeshPreview: Sendable {
    struct Batch: Sendable {
        let positions: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
        let textureCoordinates: [SIMD2<Float>]
        let indices: [UInt32]
        let textureURL: URL?
    }

    let revision: UInt64
    let batches: [Batch]
    let textureURLs: Set<URL>
    let sampledTriangleCount: Int
    let texturedTriangleCount: Int
}

/// Projects only a small, spatially distributed set of captured views for the live overlay.
/// The final USDZ exporter still considers the complete frame set for higher texture coverage.
enum LiveMeshPreviewBuilder {
    private struct MutableBatch {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var textureCoordinates: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        var textureURL: URL?
    }

    private static let maximumTextureViews = 8
    private static let maximumProjectionCandidates = 6
    // Keep the interactive preview bounded even when a room approaches the full
    // 500k-triangle capture limit. The final USDZ export still uses every face.
    private static let maximumPreviewTriangles = 60_000

    static func build(
        meshes: [LiDARSurfaceMesh],
        frames: [LiDARTextureFrame],
        revision: UInt64,
        requireForegroundMask: Bool = false,
        isCancelled: () -> Bool
    ) -> LiveMeshPreview? {
        let previewMeshes = meshes.filter {
            !$0.vertices.isEmpty && $0.indices.count.isMultiple(of: 3) && $0.triangleCount > 0
        }
        guard !previewMeshes.isEmpty else { return nil }
        let selectedFrameIndices = spatiallyDistributedFrameIndices(count: frames.count)
        var batches: [Int: MutableBatch] = [:]
        var sampledTriangles = 0
        var textured = 0
        var remainingTriangles = maximumPreviewTriangles
        var remainingMeshes = previewMeshes.count

        for mesh in previewMeshes {
            if isCancelled() { return nil }
            guard remainingTriangles > 0 else { break }
            let meshTriangleCount = mesh.triangleCount
            let meshBudget = min(meshTriangleCount, max(1, remainingTriangles / remainingMeshes))
            remainingTriangles -= meshBudget
            remainingMeshes -= 1
            let sampleStride = Double(meshTriangleCount) / Double(meshBudget)
            let center = mesh.vertices.reduce(SIMD3<Float>.zero, +) / Float(mesh.vertices.count)
            let candidates = selectedFrameIndices.sorted {
                simd_distance_squared(frames[$0].camera.position, center)
                    < simd_distance_squared(frames[$1].camera.position, center)
            }.prefix(maximumProjectionCandidates)

            for sample in 0..<meshBudget {
                if sample.isMultiple(of: 1_536), isCancelled() { return nil }
                let triangleIndex = min(meshTriangleCount - 1, Int((Double(sample) + 0.5) * sampleStride))
                let offset = triangleIndex * 3
                let triangle = (0..<3).map { mesh.vertices[Int(mesh.indices[offset + $0])] }
                guard triangle.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { continue }
                let cross = simd_cross(triangle[1] - triangle[0], triangle[2] - triangle[0])
                guard simd_length_squared(cross) > 0.0000000001 else { continue }
                sampledTriangles += 1
                let normal = simd_normalize(cross)
                var bestIndex = -1
                var bestScore: Float = 0
                var coordinates = [SIMD2<Float>](repeating: .zero, count: 3)
                for index in candidates {
                    guard let projection = frames[index].camera.projection(of: triangle),
                          projection.score > bestScore else { continue }
                    if requireForegroundMask,
                       frames[index].surfaceMask?.containsProjectedTriangle(projection.coordinates) != true {
                        continue
                    }
                    bestIndex = index
                    bestScore = projection.score
                    coordinates = projection.coordinates
                }

                if requireForegroundMask, bestIndex < 0 { continue }

                var batch = batches[bestIndex, default: MutableBatch()]
                if bestIndex >= 0 { batch.textureURL = frames[bestIndex].imageURL }
                let base = UInt32(batch.positions.count)
                batch.positions.append(contentsOf: triangle)
                batch.normals.append(contentsOf: [normal, normal, normal])
                batch.textureCoordinates.append(contentsOf: coordinates)
                batch.indices.append(contentsOf: [base, base + 1, base + 2])
                batches[bestIndex] = batch
                if bestIndex >= 0 { textured += 1 }
            }
        }

        let output = batches.keys.sorted().compactMap { index -> LiveMeshPreview.Batch? in
            guard let batch = batches[index], !batch.indices.isEmpty else { return nil }
            return LiveMeshPreview.Batch(positions: batch.positions, normals: batch.normals,
                                         textureCoordinates: batch.textureCoordinates,
                                         indices: batch.indices,
                                         textureURL: index >= 0 ? batch.textureURL : nil)
        }
        return LiveMeshPreview(revision: revision, batches: output,
                               textureURLs: Set(output.compactMap(\.textureURL)),
                               sampledTriangleCount: sampledTriangles,
                               texturedTriangleCount: textured)
    }

    private static func spatiallyDistributedFrameIndices(count: Int) -> [Int] {
        guard count > maximumTextureViews else { return Array(0..<count) }
        let denominator = Double(maximumTextureViews - 1)
        return (0..<maximumTextureViews).map { slot in
            Int((Double(slot) * Double(count - 1) / denominator).rounded())
        }
    }
}
