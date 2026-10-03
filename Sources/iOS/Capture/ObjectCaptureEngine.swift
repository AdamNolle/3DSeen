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
            trigger: capture.snapshot.coverageHapticMilestone
        )
        .onAppear { capture.start() }
        .onDisappear { capture.stop(discardUnsealedCapture: true) }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle).font(.headline)
                    Text(capture.snapshot.instruction)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Text("\(capture.snapshot.frameCount)")
                    .font(.title2.monospacedDigit().weight(.semibold))
                .accessibilityLabel("\(capture.snapshot.frameCount) photos saved")
            }

            HStack(spacing: 8) {
                Image(systemName: "circle.grid.3x3.fill")
                    .foregroundStyle(Color(red: 0.30, green: 0.72, blue: 1.0))
                Text(surfacePointStatus)
                Spacer()
                Text(capture.snapshot.surfacePointCount.formatted())
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .font(.caption.weight(.semibold))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(surfacePointStatus)
            .accessibilityValue("\(capture.snapshot.surfacePointCount) spatial samples")

            if capture.meshTriangleCount > 0 {
                VStack(spacing: 5) {
                    HStack {
                        Label("Live surface", systemImage: "cube")
                        Spacer()
                        if capture.texturedMeshTriangleCount > 0 {
                            Text("\(capture.texturedMeshTriangleCount.formatted()) textured preview faces")
                                .monospacedDigit()
                        } else if capture.liveMeshPreview != nil {
                            Text("Waiting for a clean texture view…")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Building the object surface…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.caption.weight(.medium))
                .accessibilityElement(children: .combine)
            }

            VStack(spacing: 4) {
                ProgressView(value: captureProgress)
                    .tint(Color(red: 0.38, green: 0.72, blue: 0.98))
                HStack {
                    Text("Photo set")
                    Spacer()
                    Text("\(capture.snapshot.frameCount) of \(capture.snapshot.recommendedFrameCount) recommended")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Photo set progress")
            .accessibilityValue("\(capture.snapshot.frameCount) of \(capture.snapshot.recommendedFrameCount) recommended photos")

            if showsDetails {
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
                .font(.caption)
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
                withAnimation(.easeInOut(duration: 0.2)) { showsDetails.toggle() }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
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
        return "Waiting for LiDAR depth"
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
        context.coordinator.update(points: surfacePoints, preview: liveMeshPreview)
    }

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        coordinator.detach(from: view)
    }

    @MainActor
    final class Coordinator {
        private let anchor = AnchorEntity(world: .zero)
        private let dotMesh = MeshResource.generateSphere(radius: 0.0045)
        private let dotMaterial = UnlitMaterial(
            color: UIColor(red: 0.20, green: 0.72, blue: 1.0, alpha: 1)
        )
        private weak var view: ARView?
        private var meshAnchor: AnchorEntity?
        private var meshRequests = Set<AnyCancellable>()
        private var meshTextures: [URL: TextureResource] = [:]
        private var installedMeshRevision: UInt64 = 0
        private var dots: [ModelEntity] = []
        private var previousPoints: [SIMD3<Float>] = []

        func attach(to view: ARView) {
            self.view = view
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                view.environment.sceneUnderstanding.options.insert(.occlusion)
            }
            if !view.scene.anchors.contains(where: { $0 === anchor }) {
                view.scene.addAnchor(anchor)
            }
        }

        func update(points: [SIMD3<Float>], preview: LiveMeshPreview?) {
            if points != previousPoints {
                previousPoints = points

                while dots.count < points.count {
                    let dot = ModelEntity(mesh: dotMesh, materials: [dotMaterial])
                    dot.isEnabled = false
                    anchor.addChild(dot)
                    dots.append(dot)
                }

                for (index, dot) in dots.enumerated() {
                    guard index < points.count else {
                        dot.isEnabled = false
                        continue
                    }
                    dot.position = points[index]
                    dot.isEnabled = true
                }
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
                        let entity = ModelEntity(mesh: mesh, materials: [Self.blueprintMaterial()])
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

        private static func blueprintMaterial() -> PhysicallyBasedMaterial {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(
                tint: UIColor.systemBlue.withAlphaComponent(0.42),
                texture: nil
            )
            material.roughness = 0.85
            material.faceCulling = .none
            material.blending = .transparent(opacity: 0.42)
            return material
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
            meshTextures.removeAll()
            if let meshAnchor { view.scene.anchors.remove(meshAnchor) }
            self.meshAnchor = nil
            self.view = nil
            view.scene.removeAnchor(anchor)
            dots.removeAll(keepingCapacity: false)
            previousPoints.removeAll(keepingCapacity: false)
        }
    }
}
