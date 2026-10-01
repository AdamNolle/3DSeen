import Foundation
import simd

/// World-space triangles, copied from ARKit before its Metal buffers can change.
struct LiDARSurfaceMesh: Sendable {
    let vertices: [SIMD3<Float>]
    let indices: [UInt32]

    var triangleCount: Int { indices.count / 3 }

    func validate() throws {
        guard !vertices.isEmpty, !indices.isEmpty, indices.count.isMultiple(of: 3),
              vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }),
              indices.allSatisfy({ Int($0) < vertices.count }) else {
            throw LiDARSurfaceError.invalidGeometry
        }
    }
}

/// Intrinsics describe the original, unrotated camera image. UVs therefore match the
/// unrotated JPEG, independent of how the live camera preview is oriented on screen.
struct LiDARTextureCamera: Sendable {
    let worldToCamera: simd_float4x4
    let intrinsics: simd_float3x3
    let imageWidth: Int
    let imageHeight: Int
    let depthWidth: Int
    let depthHeight: Int
    let depths: [Float]

    var position: SIMD3<Float> {
        let column = worldToCamera.inverse.columns.3
        return SIMD3(column.x, column.y, column.z)
    }

    func project(_ point: SIMD3<Float>) -> SIMD2<Float>? {
        guard imageWidth > 0, imageHeight > 0, depthWidth > 0, depthHeight > 0,
              depthWidth <= 4096, depthHeight <= 4096,
              depths.count == depthWidth * depthHeight else { return nil }
        let camera = worldToCamera * SIMD4(point, 1)
        let distance = -camera.z
        guard distance.isFinite, distance > 0.05 else { return nil }
        let x = (intrinsics.columns.0.x * camera.x / distance + intrinsics.columns.2.x) / Float(imageWidth)
        let y = (intrinsics.columns.2.y - intrinsics.columns.1.y * camera.y / distance) / Float(imageHeight)
        guard x.isFinite, y.isFinite, x > 0.005, x < 0.995, y > 0.005, y < 0.995 else { return nil }
        let column = min(depthWidth - 1, Int(x * Float(depthWidth)))
        let row = min(depthHeight - 1, Int(y * Float(depthHeight)))
        let measured = depths[row * depthWidth + column]
        // Reject occluded/background surfaces and low-confidence or missing depth samples.
        guard measured.isFinite, measured > 0,
              abs(measured - distance) <= max(0.12, distance * 0.04) else { return nil }
        return SIMD2(x, 1 - y)
    }

    func projection(of triangle: [SIMD3<Float>]) -> (coordinates: [SIMD2<Float>], score: Float)? {
        guard triangle.count == 3 else { return nil }
        let center = (triangle[0] + triangle[1] + triangle[2]) / 3
        guard project(center) != nil else { return nil }
        let coordinates = triangle.compactMap(project)
        guard coordinates.count == 3 else { return nil }
        let edgeA = coordinates[1] - coordinates[0]
        let edgeB = coordinates[2] - coordinates[0]
        let area = abs(edgeA.x * edgeB.y - edgeA.y * edgeB.x)
        guard area > 0.00000001 else { return nil }
        return (coordinates, area)
    }
}

struct LiDARTextureFrame: Sendable {
    let imageURL: URL
    let camera: LiDARTextureCamera
}

enum LiDARSurfaceError: LocalizedError {
    case invalidGeometry
    case noSurface
    case noTextures
    case tooLarge
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .invalidGeometry: return "The LiDAR surface contains invalid geometry. Retake this section."
        case .noSurface: return "No LiDAR surface was captured. Move slowly around the room before finishing."
        case .noTextures: return "No usable texture photos were saved. Scan in steady, even lighting."
        case .tooLarge: return "This scan is too large to finish safely on this device. Capture the space in smaller sections."
        case .exportFailed: return "The textured room model could not be saved. Retake this section."
        }
    }
}
