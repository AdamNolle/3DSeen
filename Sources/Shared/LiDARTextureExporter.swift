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
    }

    private struct Batch {
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var coordinates: [CGPoint] = []
    }

    static func export(
        meshes: [LiDARSurfaceMesh], frames: [LiDARTextureFrame], to outputURL: URL,
        isCancelled: @escaping () -> Bool = { false }
    ) throws -> Result {
        try validate(meshes: meshes, frames: frames)
        var batches: [Int: Batch] = [:]
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
            for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
                if offset.isMultiple(of: 192), isCancelled() { throw CancellationError() }
                let triangle = (0..<3).map { mesh.vertices[Int(mesh.indices[offset + $0])] }
                let cross = simd_cross(triangle[1] - triangle[0], triangle[2] - triangle[0])
                guard simd_length_squared(cross) > 0.0000000001 else { continue }
                var bestIndex = -1
                var bestScore: Float = 0
                var coordinates = [SIMD2<Float>](repeating: .zero, count: 3)
                for (rank, index) in candidates.enumerated() {
                    if rank >= 32, bestIndex >= 0 { break }
                    guard let projection = frames[index].camera.projection(of: triangle),
                          projection.score > bestScore else { continue }
                    bestIndex = index
                    bestScore = projection.score
                    coordinates = projection.coordinates
                }
                let normal = SCNVector3(simd_normalize(cross))
                batches[bestIndex, default: Batch()].positions.append(contentsOf: triangle.map(SCNVector3.init))
                batches[bestIndex, default: Batch()].normals.append(contentsOf: [normal, normal, normal])
                batches[bestIndex, default: Batch()].coordinates.append(contentsOf: coordinates.map {
                    CGPoint(x: CGFloat($0.x), y: CGFloat($0.y))
                })
                total += 1
                if bestIndex >= 0 { textured += 1 }
            }
        }
        guard total > 0 else { throw LiDARSurfaceError.noSurface }
        guard textured > 0 else { throw LiDARSurfaceError.noTextures }
        let scene = SCNScene()
        for index in batches.keys.sorted() {
            guard let batch = batches[index] else { continue }
            let sources = [SCNGeometrySource(vertices: batch.positions),
                           SCNGeometrySource(normals: batch.normals),
                           SCNGeometrySource(textureCoordinates: batch.coordinates)]
            let element = SCNGeometryElement(indices: (0..<batch.positions.count).map(UInt32.init), primitiveType: .triangles)
            let geometry = SCNGeometry(sources: sources, elements: [element])
            let material = SCNMaterial()
            material.name = index >= 0 ? "CapturedTexture_\(index)" : "UnobservedSurface"
            material.lightingModel = .physicallyBased
            material.isDoubleSided = true
            material.roughness.contents = 0.85
            if index >= 0 {
                material.diffuse.contents = frames[index].imageURL
                material.diffuse.wrapS = .clamp
                material.diffuse.wrapT = .clamp
            } else {
                // Preserve uncaptured geometry honestly rather than painting it with an unrelated photo.
                material.diffuse.contents = PlatformColor(white: 0.55, alpha: 1)
            }
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.name = index >= 0 ? "TexturedSurface_\(index)" : "UntexturedSurface"
            scene.rootNode.addChildNode(node)
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
        return Result(triangleCount: total, texturedTriangleCount: textured)
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
