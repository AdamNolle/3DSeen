import Foundation
import simd

/// World-space triangles, copied from ARKit before its Metal buffers can change.
struct LiDARSurfaceMesh: Sendable {
    let vertices: [SIMD3<Float>]
    let indices: [UInt32]
    /// ARKit's per-face category raw values. Empty means this device only supplied geometry.
    let classifications: [UInt8]

    init(vertices: [SIMD3<Float>], indices: [UInt32], classifications: [UInt8] = []) {
        self.vertices = vertices
        self.indices = indices
        self.classifications = classifications
    }

    var triangleCount: Int { indices.count / 3 }

    func validate() throws {
        guard !vertices.isEmpty, !indices.isEmpty, indices.count.isMultiple(of: 3),
              classifications.isEmpty || classifications.count == triangleCount,
              vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }),
              indices.allSatisfy({ Int($0) < vertices.count }) else {
            throw LiDARSurfaceError.invalidGeometry
        }
    }
}

/// ARMeshClassification values are deliberately mirrored here so shared mesh/export
/// code stays independent of ARKit and can inspect captures on macOS.
enum LiDARSurfaceClassification: Int, CaseIterable, Sendable {
    case none = 0
    case wall = 1
    case floor = 2
    case ceiling = 3
    case table = 4
    case seat = 5
    case window = 6
    case door = 7

    var label: String {
        switch self {
        case .none: return "Unclassified"
        case .wall: return "Wall"
        case .floor: return "Floor"
        case .ceiling: return "Ceiling"
        case .table: return "Table"
        case .seat: return "Seat"
        case .window: return "Window"
        case .door: return "Door"
        }
    }

    static func label(for rawValue: UInt8) -> String {
        guard let value = Self(rawValue: Int(rawValue)) else { return "Other" }
        return value.label
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
    let surfaceMask: LiDARSurfaceMask?

    init(imageURL: URL, camera: LiDARTextureCamera, surfaceMask: LiDARSurfaceMask? = nil) {
        self.imageURL = imageURL
        self.camera = camera
        self.surfaceMask = surfaceMask
    }
}

enum LiDARCaptureImageOrientation: Equatable, Sendable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight
}

/// The Vision-selected foreground instance corresponding to a captured color/depth frame.
/// Coordinates are stored in the image orientation Vision used, then queried with raw camera UVs.
struct LiDARSurfaceMask: Sendable {
    let labels: [UInt8]
    let width: Int
    let height: Int
    let selectedLabel: UInt8
    let orientation: LiDARCaptureImageOrientation

    func contains(rawNormalizedPoint point: SIMD2<Float>) -> Bool {
        let (pixelCount, didOverflow) = width.multipliedReportingOverflow(by: height)
        guard width > 0, height > 0, !didOverflow, labels.count == pixelCount,
              point.x.isFinite, point.y.isFinite,
              point.x >= 0, point.x < 1, point.y >= 0, point.y < 1 else { return false }
        let oriented: SIMD2<Float>
        switch orientation {
        case .portrait:
            oriented = SIMD2(1 - point.y, point.x)
        case .portraitUpsideDown:
            oriented = SIMD2(point.y, 1 - point.x)
        case .landscapeLeft:
            oriented = point
        case .landscapeRight:
            oriented = SIMD2(1 - point.x, 1 - point.y)
        }
        guard oriented.x >= 0, oriented.x < 1, oriented.y >= 0, oriented.y < 1 else { return false }
        let x = min(Int(oriented.x * Float(width)), width - 1)
        let y = min(Int(oriented.y * Float(height)), height - 1)
        return labels[y * width + x] == selectedLabel
    }

    /// Keep a triangle only when its center and most corners belong to the selected instance.
    /// This trims segmentation edges without allowing a single foreground pixel to admit a face.
    func containsProjectedTriangle(_ textureCoordinates: [SIMD2<Float>]) -> Bool {
        guard textureCoordinates.count == 3 else { return false }
        let imagePoints = textureCoordinates.map { SIMD2($0.x, 1 - $0.y) }
        let center = (imagePoints[0] + imagePoints[1] + imagePoints[2]) / 3
        return imagePoints.filter(contains(rawNormalizedPoint:)).count >= 2
            && contains(rawNormalizedPoint: center)
    }
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
