import Foundation
import simd

struct LiveMeshPreview: Sendable {
    struct Batch: Sendable {
        let positions: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
        let textureCoordinates: [SIMD2<Float>]
        let indices: [UInt32]
        let textureURL: URL?
        let objectIdentifier: Int?
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
    private struct BatchKey: Hashable {
        let frameIndex: Int
        let objectIdentifier: Int?
    }

    private struct Selection {
        let frameIndex: Int
        let objectIdentifier: Int?
        let coordinates: [SIMD2<Float>]
    }

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
        var batches: [BatchKey: MutableBatch] = [:]
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
            let roomCandidates = Array(selectedFrameIndices.sorted {
                simd_distance_squared(frames[$0].camera.position, center)
                    < simd_distance_squared(frames[$1].camera.position, center)
            }.prefix(maximumProjectionCandidates))
            let objectCandidates = Array(frames.indices
                .filter { frames[$0].objectMask != nil }
                .sorted {
                    simd_distance_squared(frames[$0].camera.position, center)
                        < simd_distance_squared(frames[$1].camera.position, center)
                }
                .prefix(maximumProjectionCandidates))

            for sample in 0..<meshBudget {
                if sample.isMultiple(of: 1_536), isCancelled() { return nil }
                let triangleIndex = min(meshTriangleCount - 1, Int((Double(sample) + 0.5) * sampleStride))
                let offset = triangleIndex * 3
                let triangle = (0..<3).map { mesh.vertices[Int(mesh.indices[offset + $0])] }
                guard triangle.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
                    continue
                }
                let cross = simd_cross(triangle[1] - triangle[0], triangle[2] - triangle[0])
                guard simd_length_squared(cross) > 0.0000000001 else { continue }
                sampledTriangles += 1
                let normal = simd_normalize(cross)
                guard let selection = bestSelection(
                    for: triangle,
                    roomCandidates: roomCandidates,
                    objectCandidates: objectCandidates,
                    frames: frames,
                    requireForegroundMask: requireForegroundMask
                ) else { continue }
                let key = BatchKey(frameIndex: selection.frameIndex, objectIdentifier: selection.objectIdentifier)
                var batch = batches[key, default: MutableBatch()]
                if selection.frameIndex >= 0 { batch.textureURL = frames[selection.frameIndex].imageURL }
                let base = UInt32(batch.positions.count)
                batch.positions.append(contentsOf: triangle)
                batch.normals.append(contentsOf: [normal, normal, normal])
                batch.textureCoordinates.append(contentsOf: selection.coordinates)
                batch.indices.append(contentsOf: [base, base + 1, base + 2])
                batches[key] = batch
                if selection.frameIndex >= 0 { textured += 1 }
            }
        }

        let output = batches.keys.sorted {
            let leftObject = $0.objectIdentifier ?? 0
            let rightObject = $1.objectIdentifier ?? 0
            return leftObject == rightObject
                ? $0.frameIndex < $1.frameIndex
                : leftObject < rightObject
        }.compactMap { key -> LiveMeshPreview.Batch? in
            guard let batch = batches[key], !batch.indices.isEmpty else { return nil }
            return LiveMeshPreview.Batch(
                positions: batch.positions,
                normals: batch.normals,
                textureCoordinates: batch.textureCoordinates,
                indices: batch.indices,
                textureURL: key.frameIndex >= 0 ? batch.textureURL : nil,
                objectIdentifier: key.objectIdentifier
            )
        }
        return LiveMeshPreview(
            revision: revision,
            batches: output,
            textureURLs: Set(output.compactMap(\.textureURL)),
            sampledTriangleCount: sampledTriangles,
            texturedTriangleCount: textured
        )
    }

    private static func bestSelection(
        for triangle: [SIMD3<Float>],
        roomCandidates: [Int],
        objectCandidates: [Int],
        frames: [LiDARTextureFrame],
        requireForegroundMask: Bool
    ) -> Selection? {
        var bestRoomIndex = -1
        var bestRoomScore: Float = 0
        var roomCoordinates = [SIMD2<Float>](repeating: .zero, count: 3)
        for index in roomCandidates {
            guard let projection = frames[index].camera.projection(of: triangle),
                  projection.score > bestRoomScore else { continue }
            if requireForegroundMask,
               frames[index].surfaceMask?.containsProjectedTriangle(projection.coordinates) != true {
                continue
            }
            bestRoomIndex = index
            bestRoomScore = projection.score
            roomCoordinates = projection.coordinates
        }

        guard !requireForegroundMask || bestRoomIndex >= 0 else { return nil }
        var bestObjectIndex = -1
        var bestObjectIdentifier: Int?
        var bestObjectScore: Float = 0
        var objectCoordinates = [SIMD2<Float>](repeating: .zero, count: 3)
        if !requireForegroundMask {
            for index in objectCandidates {
                guard let projection = frames[index].camera.projection(of: triangle),
                      let identifier = frames[index].objectMask?.objectIdentifier(
                        containingProjectedTriangle: projection.coordinates
                      ), projection.score > bestObjectScore else { continue }
                bestObjectIndex = index
                bestObjectIdentifier = identifier
                bestObjectScore = projection.score
                objectCoordinates = projection.coordinates
            }
        }

        if bestObjectIndex >= 0 {
            return Selection(
                frameIndex: bestObjectIndex,
                objectIdentifier: bestObjectIdentifier,
                coordinates: objectCoordinates
            )
        }
        return Selection(frameIndex: bestRoomIndex, objectIdentifier: nil, coordinates: roomCoordinates)
    }

    private static func spatiallyDistributedFrameIndices(count: Int) -> [Int] {
        guard count > maximumTextureViews else { return Array(0..<count) }
        let denominator = Double(maximumTextureViews - 1)
        return (0..<maximumTextureViews).map { slot in
            Int((Double(slot) * Double(count - 1) / denominator).rounded())
        }
    }
}
