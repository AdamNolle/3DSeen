import SwiftUI
import RealityKit
import Combine
import UIKit
import ARKit

struct RoomSurfaceARView: UIViewRepresentable {
    let controller: RoomCaptureController
    let surfacePoints: [SIMD3<Float>]
    let surfacePointRevision: UInt64
    let objectPoints: [SIMD3<Float>]
    let objectPointRevision: UInt64

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
        context.coordinator.update(
            surfacePoints: surfacePoints,
            surfaceRevision: surfacePointRevision,
            objectPoints: objectPoints,
            objectRevision: objectPointRevision
        )
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.detach(from: uiView)
    }

    @MainActor
    final class Coordinator {
        private let anchor = AnchorEntity(world: .zero)
        private let dotEntity = ModelEntity()
        private let objectDotEntity = ModelEntity()
        private let dotMaterial: PhysicallyBasedMaterial = {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: UIColor(red: 0.12, green: 0.66, blue: 1, alpha: 1), texture: nil)
            material.roughness = 0.38
            return material
        }()
        private let objectDotMaterial: PhysicallyBasedMaterial = {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: UIColor(red: 0.88, green: 0.96, blue: 1, alpha: 1), texture: nil)
            material.roughness = 0.32
            return material
        }()
        private let dotBuildQueue = DispatchQueue(label: "com.adamnolle.3DSeen.room-surface-dots", qos: .userInitiated)
        private weak var view: ARView?
        private var meshRequests = Set<AnyCancellable>()
        private var revision: UInt64 = 0
        private var previousSurfaceRevision: UInt64?
        private var previousObjectRevision: UInt64?
        private var pendingPoints: (surface: [SIMD3<Float>], objects: [SIMD3<Float>])?
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
            if !anchor.children.contains(where: { $0 === objectDotEntity }) {
                anchor.addChild(objectDotEntity)
            }
        }

        func update(
            surfacePoints: [SIMD3<Float>],
            surfaceRevision: UInt64,
            objectPoints: [SIMD3<Float>],
            objectRevision: UInt64
        ) {
            guard surfaceRevision != previousSurfaceRevision || objectRevision != previousObjectRevision else { return }
            previousSurfaceRevision = surfaceRevision
            previousObjectRevision = objectRevision
            revision &+= 1
            guard !surfacePoints.isEmpty || !objectPoints.isEmpty else {
                pendingPoints = nil
                meshRequests.removeAll()
                dotEntity.model = nil
                objectDotEntity.model = nil
                return
            }
            pendingPoints = (surfacePoints, objectPoints)
            scheduleDotMeshBuildIfNeeded()
        }

        func detach(from view: ARView) {
            meshRequests.removeAll()
            pendingPoints = nil
            revision &+= 1
            previousSurfaceRevision = nil
            previousObjectRevision = nil
            view.scene.anchors.remove(anchor)
            self.view = nil
        }

        private func scheduleDotMeshBuildIfNeeded() {
            guard !buildInFlight, let points = pendingPoints else { return }
            pendingPoints = nil
            buildInFlight = true
            let buildRevision = revision
            dotBuildQueue.async { [weak self] in
                let surfaceGeometry = GuidedSurfaceDotMesh.build(points: points.surface)
                let objectGeometry = GuidedSurfaceDotMesh.build(points: points.objects, radius: 0.0055)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.buildInFlight = false
                    if self.revision == buildRevision, self.view != nil {
                        self.meshRequests.removeAll()
                        self.installDotMesh(surfaceGeometry, on: self.dotEntity, material: self.dotMaterial,
                                            name: "GuidedRoomSurfaceDots", revision: buildRevision)
                        self.installDotMesh(objectGeometry, on: self.objectDotEntity, material: self.objectDotMaterial,
                                            name: "TrackedObjectSurfaceDots", revision: buildRevision)
                    }
                    self.scheduleDotMeshBuildIfNeeded()
                }
            }
        }

        private func installDotMesh(
            _ geometry: GuidedSurfaceDotMesh,
            on entity: ModelEntity,
            material: PhysicallyBasedMaterial,
            name: String,
            revision: UInt64
        ) {
            guard !geometry.positions.isEmpty else {
                entity.model = nil
                return
            }
            var descriptor = MeshDescriptor(name: name)
            descriptor.positions = MeshBuffers.Positions(geometry.positions)
            descriptor.normals = MeshBuffers.Normals(geometry.normals)
            descriptor.primitives = .triangles(geometry.triangleIndices)
            MeshResource.generateAsync(from: [descriptor])
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { [weak self, weak entity] mesh in
                        guard let self, let entity, self.revision == revision, self.view != nil else { return }
                        entity.model = ModelComponent(mesh: mesh, materials: [material])
                    }
                )
                .store(in: &meshRequests)
        }
    }
}
