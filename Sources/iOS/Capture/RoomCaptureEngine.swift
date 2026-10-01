import SwiftUI
import ARKit
import RealityKit

/// LiDAR captures measured surface topology while the camera supplies its appearance.
struct RoomCaptureEngine: View {
    @EnvironmentObject var stateMachine: ProcessingStateMachine
    let attemptID: UUID
    @StateObject private var controller = RoomCaptureController()

    var body: some View {
        ZStack {
            RoomSurfaceARView(controller: controller).ignoresSafeArea()
            LiveCaptureHUD(
                status: LiveCaptureStatus(mode: .space, phase: controller.isProcessing ? .processing : .capturing,
                                          frameCount: controller.frameCount, trackingStatus: controller.status,
                                          surfaceTriangleCount: controller.triangleCount),
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
    }
}

/// All mesh/frame storage is confined to the delegate queue. Cancellation is shared
/// through a lock so an in-flight export cannot publish a discarded capture.
final class RoomCaptureController: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    @Published private(set) var frameCount = 0
    @Published private(set) var textureCount = 0
    @Published private(set) var triangleCount = 0
    @Published private(set) var isProcessing = false
    @Published private(set) var status = "Starting LiDAR"
    var onExported: ((URL) -> Void)?
    var onFailure: ((String) -> Void)?

    private let queue = DispatchQueue(label: "com.adamnolle.3DSeen.surface-capture", qos: .userInitiated)
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
    private var lastCameraTransform: simd_float4x4?

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
                config.sceneReconstruction = .mesh
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
                let report = LiDARCaptureReport(schemaVersion: 1, triangleCount: result.triangleCount,
                                                texturedTriangleCount: result.texturedTriangleCount,
                                                textureFrameCount: frames.count, textureSnapshotCount: snapshotCount)
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
    }

    private func update(_ anchors: [ARAnchor]) {
        guard accepting, !isCancelled else { return }
        do {
            for anchor in anchors.compactMap({ $0 as? ARMeshAnchor }) where anchor.geometry.faces.count >= 1 {
                meshes[anchor.identifier] = try LiDARCaptureFrames.mesh(anchor)
            }
            guard meshes.values.reduce(0, { $0 + $1.triangleCount }) <= 500_000 else { throw LiDARSurfaceError.tooLarge }
            let count = meshes.values.reduce(0, { $0 + $1.triangleCount })
            publish { $0.triangleCount = count }
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
        } catch { fail(error) }
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
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = controller.session
        return view
    }
    func updateUIView(_ uiView: ARView, context: Context) {}
}
