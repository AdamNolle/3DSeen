import Foundation
import ImageIO
import SceneKit
import simd

/// Uses Apple's USDZ exporter so image dependencies are embedded in a portable model.
/// No box fitting, plane flattening, synthetic geometry, or invented surface colors.
enum LiDARTextureExporter {
    struct Result: Sendable {
        let triangleCount: Int
        let texturedTriangleCount: Int
        let surfaceCounts: [String: Int]
        let trackedObjectCount: Int
    }

    private struct BatchKey: Hashable {
        let frameIndex: Int
        let classification: UInt8
        let objectIdentifier: Int?
    }

    private struct Batch {
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var coordinates: [CGPoint] = []
    }

    private struct TextureSelection {
        let frameIndex: Int
        let objectIdentifier: Int?
        let coordinates: [SIMD2<Float>]
    }

    private struct TextureCandidates {
        let room: [Int]
        let foreground: [Int]
        let objects: [Int]
    }

    static func export(
        meshes: [LiDARSurfaceMesh], frames: [LiDARTextureFrame], to outputURL: URL,
        requireForegroundMask: Bool = false,
        isCancelled: @escaping () -> Bool = { false }
    ) throws -> Result {
        try validate(meshes: meshes, frames: frames)
        var batches: [BatchKey: Batch] = [:]
        var surfaceCounts: [String: Int] = [:]
        var total = 0
        var textured = 0
        let cameraPositions = frames.map { $0.camera.position }
        for mesh in meshes {
            if isCancelled() { throw CancellationError() }
            try mesh.validate()
            let center = mesh.vertices.reduce(SIMD3<Float>.zero, +) / Float(mesh.vertices.count)
            // Try nearby views first, but retain farther views when those cannot see a face.
            let candidates = frames.indices.sorted {
                simd_distance_squared(cameraPositions[$0], center)
                    < simd_distance_squared(cameraPositions[$1], center)
            }
            let textureCandidates = TextureCandidates(
                room: candidates,
                foreground: candidates.filter { frames[$0].surfaceMask != nil },
                objects: candidates.filter { frames[$0].objectMask != nil }
            )
            for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
                if offset.isMultiple(of: 192), isCancelled() { throw CancellationError() }
                let triangle = (0..<3).map { mesh.vertices[Int(mesh.indices[offset + $0])] }
                let cross = simd_cross(triangle[1] - triangle[0], triangle[2] - triangle[0])
                guard simd_length_squared(cross) > 0.0000000001 else { continue }
                let faceIndex = offset / 3
                let classification = mesh.classifications.isEmpty ? 0 : mesh.classifications[faceIndex]
                guard let selection = Self.bestTextureSelection(
                    for: triangle,
                    candidates: textureCandidates,
                    frames: frames,
                    requireForegroundMask: requireForegroundMask
                ) else { continue }
                let normal = SCNVector3(simd_normalize(cross))
                let key = BatchKey(
                    frameIndex: selection.frameIndex,
                    classification: classification,
                    objectIdentifier: selection.objectIdentifier
                )
                var batch = batches[key, default: Batch()]
                batch.positions.append(contentsOf: triangle.map(SCNVector3.init))
                batch.normals.append(contentsOf: [normal, normal, normal])
                batch.coordinates.append(contentsOf: selection.coordinates.map {
                    CGPoint(x: CGFloat($0.x), y: CGFloat($0.y))
                })
                batches[key] = batch
                let label = LiDARSurfaceClassification.label(for: classification)
                surfaceCounts[label, default: 0] += 1
                total += 1
                if selection.frameIndex >= 0 { textured += 1 }
            }
        }
        guard total > 0 else { throw LiDARSurfaceError.noSurface }
        guard textured > 0 else { throw LiDARSurfaceError.noTextures }
        let scene = SCNScene()
        var objectNodes: [Int: SCNNode] = [:]
        for key in batches.keys.sorted(by: {
            ($0.objectIdentifier ?? 0, $0.classification, $0.frameIndex)
                < ($1.objectIdentifier ?? 0, $1.classification, $1.frameIndex)
        }) {
            guard let batch = batches[key] else { continue }
            let category = LiDARSurfaceClassification.label(for: key.classification)
            let sources = [SCNGeometrySource(vertices: batch.positions),
                           SCNGeometrySource(normals: batch.normals),
                           SCNGeometrySource(textureCoordinates: batch.coordinates)]
            let element = SCNGeometryElement(indices: (0..<batch.positions.count).map(UInt32.init), primitiveType: .triangles)
            let geometry = SCNGeometry(sources: sources, elements: [element])
            let material = SCNMaterial()
            let objectSuffix = key.objectIdentifier.map { "Object_\($0)_" } ?? ""
            material.name = key.frameIndex >= 0
                ? "CapturedTexture_\(key.frameIndex)_\(objectSuffix)\(category)"
                : "UnobservedSurface_\(objectSuffix)\(category)"
            material.lightingModel = .physicallyBased
            material.isDoubleSided = true
            material.roughness.contents = 0.85
            if key.frameIndex >= 0 {
                material.diffuse.contents = frames[key.frameIndex].imageURL
                material.diffuse.wrapS = .clamp
                material.diffuse.wrapT = .clamp
            } else {
                // Preserve uncaptured geometry honestly rather than painting it with an unrelated photo.
                material.diffuse.contents = PlatformColor(white: 0.55, alpha: 1)
            }
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            let objectPrefix = key.objectIdentifier.map { "Object \($0) · " } ?? ""
            let name = objectPrefix + "\(category) Surface"
                + (key.frameIndex >= 0 ? " · View \(key.frameIndex + 1)" : "")
            geometry.name = name
            node.name = name
            if let objectIdentifier = key.objectIdentifier {
                let objectNode: SCNNode
                if let existing = objectNodes[objectIdentifier] {
                    objectNode = existing
                } else {
                    objectNode = SCNNode()
                    objectNode.name = String(format: "Object %02d", objectIdentifier)
                    scene.rootNode.addChildNode(objectNode)
                    objectNodes[objectIdentifier] = objectNode
                }
                objectNode.addChildNode(node)
            } else {
                scene.rootNode.addChildNode(node)
            }
        }
        if isCancelled() { throw CancellationError() }
        let staging = outputURL.deletingLastPathComponent().appendingPathComponent(".pending-\(UUID().uuidString).usdz")
        defer { try? FileManager.default.removeItem(at: staging) }
        let success = scene.write(to: staging, options: nil, delegate: nil) { _, _, stop in
            if isCancelled() { stop.pointee = true }
        }
        if isCancelled() { throw CancellationError() }
        guard success, ModelGeometryInspector.inspect(modelURL: staging)?.triangleCount == total else {
            throw LiDARSurfaceError.exportFailed
        }
        try FileManager.default.moveItem(at: staging, to: outputURL)
        return Result(
            triangleCount: total,
            texturedTriangleCount: textured,
            surfaceCounts: surfaceCounts,
            trackedObjectCount: objectNodes.count
        )
    }

    private static func bestTextureSelection(
        for triangle: [SIMD3<Float>],
        candidates: TextureCandidates,
        frames: [LiDARTextureFrame],
        requireForegroundMask: Bool
    ) -> TextureSelection? {
        var bestObjectIndex = -1
        var bestObjectIdentifier: Int?
        var bestObjectScore: Float = 0
        var objectCoordinates = [SIMD2<Float>](repeating: .zero, count: 3)
        var bestRoomIndex = -1
        var bestRoomScore: Float = 0
        var roomCoordinates = [SIMD2<Float>](repeating: .zero, count: 3)

        let roomFrames = requireForegroundMask ? candidates.foreground : candidates.room
        for (rank, index) in roomFrames.enumerated() {
            if rank >= 32, bestRoomIndex >= 0 { break }
            guard let projection = frames[index].camera.projection(of: triangle) else { continue }
            if requireForegroundMask {
                guard projection.score > bestRoomScore,
                      frames[index].surfaceMask?.containsProjectedTriangle(projection.coordinates) == true
                else { continue }
                bestRoomIndex = index
                bestRoomScore = projection.score
                roomCoordinates = projection.coordinates
            } else if projection.score > bestRoomScore {
                bestRoomIndex = index
                bestRoomScore = projection.score
                roomCoordinates = projection.coordinates
            }
        }

        if !requireForegroundMask {
            for (rank, index) in candidates.objects.enumerated() {
                if rank >= 32, bestObjectIndex >= 0 { break }
                guard let projection = frames[index].camera.projection(of: triangle),
                      let identifier = frames[index].objectMask?.objectIdentifier(
                        containingProjectedTriangle: projection.coordinates
                      ) else { continue }
                guard projection.score > bestObjectScore else { continue }
                bestObjectIndex = index
                bestObjectIdentifier = identifier
                bestObjectScore = projection.score
                objectCoordinates = projection.coordinates
            }
        }

        if requireForegroundMask, bestRoomIndex < 0 { return nil }
        if bestObjectIndex >= 0 {
            return TextureSelection(
                frameIndex: bestObjectIndex,
                objectIdentifier: bestObjectIdentifier,
                coordinates: objectCoordinates
            )
        }
        return TextureSelection(frameIndex: bestRoomIndex, objectIdentifier: nil, coordinates: roomCoordinates)
    }

    private static func validate(meshes: [LiDARSurfaceMesh], frames: [LiDARTextureFrame]) throws {
        guard !meshes.isEmpty else { throw LiDARSurfaceError.noSurface }
        guard !frames.isEmpty else { throw LiDARSurfaceError.noTextures }
        guard frames.allSatisfy({ frame in
            guard let image = CGImageSourceCreateWithURL(frame.imageURL as CFURL, nil) else { return false }
            return CGImageSourceCreateImageAtIndex(image, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil
        }) else { throw LiDARSurfaceError.noTextures }
        guard meshes.reduce(0, { $0 + $1.triangleCount }) <= 500_000 else {
            throw LiDARSurfaceError.tooLarge
        }
    }
}
