import ARKit
import Combine
import RealityKit
import SwiftUI
import UIKit

struct ObjectCaptureEngine: View {
    @EnvironmentObject private var stateMachine: ProcessingStateMachine
    @StateObject private var capture: GuidedObjectCaptureController
    @State private var showsDetails = false
    let attemptID: UUID

    init(attemptID: UUID, recommendedFrameCount: Int = 48) {
        self.attemptID = attemptID
        _capture = StateObject(wrappedValue: GuidedObjectCaptureController(
            recommendedFrameCount: recommendedFrameCount
        ))
    }

    var body: some View {
        ZStack {
            GuidedObjectARView(
                controller: capture,
                surfacePoints: capture.snapshot.surfacePoints,
                surfacePointRevision: capture.snapshot.surfacePointRevision,
                liveMeshPreview: capture.liveMeshPreview
            )
            .ignoresSafeArea()
            GuidedTrackingOverlay(
                snapshot: capture.snapshot,
                showsScreenPoints: capture.snapshot.pointSource != .lidarDepth
            )
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                Spacer()
                controls
            }
        }
        .background(Color.black)
        .sensoryFeedback(
            .impact(weight: .light, intensity: 0.55),
            trigger: capture.snapshot.coverageHapticPulseRevision
        )
        .onAppear { capture.start() }
        .onDisappear { capture.stop(discardUnsealedCapture: true) }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.sf(17, .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle).font(.sf(16, .semibold))
                    Text(capture.snapshot.instruction)
                        .font(.sf(13.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Text("\(capture.snapshot.frameCount)")
                    .font(.sf(18, .semibold).monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.12), in: Capsule())
                    .accessibilityLabel("\(capture.snapshot.frameCount) photos saved")
            }

            HStack(spacing: 8) {
                Image(systemName: "circle.grid.3x3.fill")
                    .foregroundStyle(Color(red: 0.30, green: 0.72, blue: 1.0))
                Text(surfacePointStatus)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text(capture.snapshot.surfacePointCount.formatted())
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.18), value: capture.snapshot.surfacePointCount)
            }
            .font(.caption.weight(.semibold))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(surfacePointStatus)
            .accessibilityValue("\(capture.snapshot.surfacePointCount) spatial samples")

            VStack(spacing: 4) {
                ProgressView(value: captureProgress)
                    .tint(Color(red: 0.38, green: 0.72, blue: 0.98))
                HStack {
                    Text("Photo set")
                    Spacer()
                    Text("\(capture.snapshot.frameCount) / \(capture.snapshot.recommendedFrameCount) recommended")
                }
                .font(.sf(11.5, .medium))
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Photo set progress")
            .accessibilityValue("\(capture.snapshot.frameCount) of \(capture.snapshot.recommendedFrameCount) recommended photos")

            if showsDetails {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: surfacePointDetailIcon)
                            .font(.caption2.weight(.semibold))
                        Text(surfacePointDetail)
                            .font(.caption2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }

                    if capture.meshTriangleCount > 0 {
                        HStack {
                            Label("Live surface", systemImage: "cube")
                            Spacer()
                            if capture.texturedMeshTriangleCount > 0 {
                                Text("\(capture.texturedMeshTriangleCount.formatted()) textured faces")
                                    .monospacedDigit()
                            } else if capture.liveMeshPreview != nil {
                                Text("Waiting for a clean texture view…")
                            } else {
                                Text("Building the object surface…")
                            }
                        }
                    }

                    HStack {
                        Label(
                            capture.snapshot.isSubjectLocked ? "subject locked" : "finding subject",
                            systemImage: capture.snapshot.isSubjectLocked ? "lock.fill" : "lock.open"
                        )
                        Spacer()
                        Label(
                            capture.snapshot.pointSource?.rawValue ?? capture.snapshot.trackingStatus,
                            systemImage: "circle.grid.cross"
                        )
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if capture.snapshot.phase == .failed {
                HStack(spacing: 10) {
                    Button(action: capture.retry) {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: finish) {
                        Label("Finish", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(capture.snapshot.frameCount == 0)
                }
            } else {
                captureControls
            }

            Button(showsDetails ? "Hide scan details" : "Show scan details") {
                showsDetails.toggle()
            }
            .font(.sf(12, .semibold))
            .foregroundStyle(Color(red: 0.56, green: 0.78, blue: 1))
            .frame(minHeight: 40)
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: 520)
        .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
    }

    private var captureControls: some View {
        HStack(spacing: 10) {
                Button {
                    capture.setAutoCaptureEnabled(!capture.snapshot.isAutoCaptureEnabled)
                } label: {
                    Label(
                        capture.snapshot.isAutoCaptureEnabled ? "Pause Auto" : "Resume Auto",
                        systemImage: capture.snapshot.isAutoCaptureEnabled ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(capture.snapshot.isFinishing)

                Button(action: capture.captureManually) {
                    Label("Photo", systemImage: "camera.shutter.button")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(capture.snapshot.isFinishing)

                Button(action: finish) {
                    Label("Finish", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(capture.snapshot.frameCount == 0 || capture.snapshot.isFinishing)
        }
    }

    private var captureProgress: Double {
        min(1, Double(capture.snapshot.frameCount) / Double(capture.snapshot.recommendedFrameCount))
    }

    private var statusTitle: String {
        switch capture.snapshot.phase {
        case .starting: return "Starting camera"
        case .seekingSubject: return "Finding your object"
        case .capturing: return "Object detected"
        case .finalizing: return "Saving scan"
        case .failed: return "Capture needs attention"
        }
    }

    private var statusIcon: String {
        capture.snapshot.phase == .capturing ? "scope" : "viewfinder"
    }

    private var statusColor: Color {
        capture.snapshot.phase == .capturing
            ? Color(red: 0.38, green: 0.72, blue: 0.98)
            : .white
    }

    private var surfacePointStatus: String {
        if capture.snapshot.surfacePointCount > 0 || capture.snapshot.pointSource == .lidarDepth {
            return "3D LiDAR surface dots"
        }
        if capture.snapshot.pointSource == .visualFeatures {
            return "AR feature points · depth unavailable"
        }
        return supportsLiDARDepth ? "Waiting for LiDAR depth" : "AR feature points · no LiDAR sensor"
    }

    private var surfacePointDetail: String {
        if capture.snapshot.surfaceCoverageLimitReached {
            return "Surface map is full. Finish this scan before capturing more."
        }
        switch capture.snapshot.pointSource {
        case .lidarDepth:
            return "Dots stay pinned in 3D; a gentle tap marks newly mapped surface area."
        case .visualFeatures:
            return "Screen-space guidance only; LiDAR depth is unavailable."
        case nil:
            return supportsLiDARDepth
                ? "LiDAR depth pins scan dots directly to the object."
                : "This device uses tracked points; depth-pinned dots require LiDAR."
        }
    }

    private var surfacePointDetailIcon: String {
        capture.snapshot.pointSource == .lidarDepth ? "waveform" : "info.circle"
    }

    private var supportsLiDARDepth: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
            || ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    private func finish() {
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

private struct GuidedTrackingOverlay: View {
    let snapshot: GuidedScanSnapshot
    let showsScreenPoints: Bool

    var body: some View {
        Canvas { context, _ in
            if let bounds = snapshot.subjectBounds {
                context.stroke(
                    Path(roundedRect: bounds, cornerRadius: 20),
                    with: .color(.white.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 2, dash: [9, 7])
                )
            }
            if showsScreenPoints {
                for point in snapshot.points {
                    let rect = CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.86)))
                    context.stroke(Path(ellipseIn: rect), with: .color(.blue.opacity(0.55)), lineWidth: 1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct GuidedObjectARView: UIViewRepresentable {
    let controller: GuidedObjectCaptureController
    let surfacePoints: [SIMD3<Float>]
    let surfacePointRevision: UInt64
    let liveMeshPreview: LiveMeshPreview?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = controller.session
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        controller.updatePresentation(
            viewportSize: view.bounds.size,
            orientation: view.window?.windowScene?.interfaceOrientation ?? .portrait
        )
        context.coordinator.update(
            points: surfacePoints,
            pointRevision: surfacePointRevision,
            preview: liveMeshPreview
        )
    }

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        coordinator.detach(from: view)
    }

    @MainActor
    final class Coordinator {
        private let anchor = AnchorEntity(world: .zero)
        private let dotEntity = ModelEntity()
        private let dotMaterial = UnlitMaterial(
            color: UIColor(red: 0.20, green: 0.72, blue: 1.0, alpha: 1)
        )
        private let dotBuildQueue = DispatchQueue(label: "com.adamnolle.3DSeen.surface-dots", qos: .userInitiated)
        private weak var view: ARView?
        private var meshAnchor: AnchorEntity?
        private var meshRequests = Set<AnyCancellable>()
        private var dotMeshRequests = Set<AnyCancellable>()
        private var meshTextures: [URL: TextureResource] = [:]
        private var installedMeshRevision: UInt64 = 0
        private var dotRevision: UInt64 = 0
        private var dotBuildInFlight = false
        private var pendingDotPoints: [SIMD3<Float>]?
        private var previousPointRevision: UInt64?

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

        func update(points: [SIMD3<Float>], pointRevision: UInt64, preview: LiveMeshPreview?) {
            if pointRevision != previousPointRevision {
                previousPointRevision = pointRevision
                rebuildDotMesh(with: points)
            }
            if let preview {
                install(preview)
            } else if let meshAnchor {
                meshRequests.removeAll()
                view?.scene.anchors.remove(meshAnchor)
                self.meshAnchor = nil
                installedMeshRevision = 0
            }
        }

        private func rebuildDotMesh(with points: [SIMD3<Float>]) {
            dotRevision &+= 1
            guard !points.isEmpty else {
                pendingDotPoints = nil
                dotMeshRequests.removeAll()
                dotEntity.model = nil
                return
            }
            pendingDotPoints = points
            scheduleDotMeshBuildIfNeeded()
        }

        private func scheduleDotMeshBuildIfNeeded() {
            guard !dotBuildInFlight, let points = pendingDotPoints else { return }
            pendingDotPoints = nil
            dotBuildInFlight = true
            let revision = dotRevision
            dotBuildQueue.async { [weak self] in
                let geometry = GuidedSurfaceDotMesh.build(points: points)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.dotBuildInFlight = false
                    if self.dotRevision == revision, self.view != nil {
                        self.installDotMesh(geometry, revision: revision)
                    }
                    self.scheduleDotMeshBuildIfNeeded()
                }
            }
        }

        private func installDotMesh(_ geometry: GuidedSurfaceDotMesh, revision: UInt64) {
            dotMeshRequests.removeAll()
            guard !geometry.positions.isEmpty else {
                dotEntity.model = nil
                return
            }
            var descriptor = MeshDescriptor(name: "GuidedObjectSurfaceDots")
            descriptor.positions = MeshBuffers.Positions(geometry.positions)
            descriptor.normals = MeshBuffers.Normals(geometry.normals)
            descriptor.primitives = .triangles(geometry.triangleIndices)
            MeshResource.generateAsync(from: [descriptor])
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { [weak self] mesh in
                        guard let self, self.dotRevision == revision, self.view != nil else { return }
                        self.dotEntity.model = ModelComponent(mesh: mesh, materials: [self.dotMaterial])
                    }
                )
                .store(in: &dotMeshRequests)
        }

        private func install(_ preview: LiveMeshPreview) {
            guard preview.revision > installedMeshRevision, let view else { return }
            installedMeshRevision = preview.revision
            meshRequests.removeAll()
            meshTextures = meshTextures.filter { preview.textureURLs.contains($0.key) }
            if let meshAnchor { view.scene.anchors.remove(meshAnchor) }
            let nextAnchor = AnchorEntity(world: .zero)
            meshAnchor = nextAnchor
            view.scene.anchors.append(nextAnchor)

            for batch in preview.batches {
                var descriptor = MeshDescriptor(name: "LiveObjectSurface")
                descriptor.positions = MeshBuffers.Positions(batch.positions)
                descriptor.normals = MeshBuffers.Normals(batch.normals)
                descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(batch.textureCoordinates)
                descriptor.primitives = .triangles(batch.indices)
                MeshResource.generateAsync(from: [descriptor])
                    .receive(on: DispatchQueue.main)
                    .sink(
                        receiveCompletion: { _ in },
                        receiveValue: { [weak self, weak nextAnchor] mesh in
                        guard let self, let nextAnchor,
                              self.installedMeshRevision == preview.revision else { return }
                        let entity = ModelEntity(
                            mesh: mesh,
                            materials: [CapturePreviewMaterials.blueprintSurface()]
                        )
                        nextAnchor.addChild(entity)
                        guard let textureURL = batch.textureURL else { return }
                        if let texture = self.meshTextures[textureURL] {
                            entity.model?.materials = [Self.texturedMaterial(texture)]
                            return
                        }
                        TextureResource.loadAsync(
                            contentsOf: textureURL,
                            withName: "object-\(preview.revision)-\(textureURL.lastPathComponent)"
                        )
                            .receive(on: DispatchQueue.main)
                            .sink(
                                receiveCompletion: { _ in },
                                receiveValue: { [weak self, weak entity] texture in
                                guard let self, let entity,
                                      self.installedMeshRevision == preview.revision else { return }
                                self.meshTextures[textureURL] = texture
                                entity.model?.materials = [Self.texturedMaterial(texture)]
                                }
                            )
                            .store(in: &self.meshRequests)
                        }
                    )
                    .store(in: &meshRequests)
            }
        }

        private static func texturedMaterial(_ texture: TextureResource) -> PhysicallyBasedMaterial {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .white, texture: .init(texture))
            material.roughness = 0.85
            material.faceCulling = .none
            return material
        }

        func detach(from view: ARView) {
            meshRequests.removeAll()
            dotRevision &+= 1
            pendingDotPoints = nil
            dotMeshRequests.removeAll()
            dotEntity.model = nil
            meshTextures.removeAll()
            if let meshAnchor { view.scene.anchors.remove(meshAnchor) }
            self.meshAnchor = nil
            self.view = nil
            view.scene.removeAnchor(anchor)
            previousPointRevision = nil
        }
    }
}
