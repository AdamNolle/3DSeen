import Foundation
import simd

enum GuidedDepthProjection {
    /// Unprojects one captured-image pixel using ARKit's camera intrinsics,
    /// then places it in the stable world coordinate system of the AR session.
    static func worldPosition(
        pixel: SIMD2<Float>,
        depth: Float,
        focalLength: SIMD2<Float>,
        principalPoint: SIMD2<Float>,
        cameraTransform: simd_float4x4
    ) -> SIMD3<Float>? {
        guard pixel.x.isFinite, pixel.y.isFinite,
              depth.isFinite, depth > 0,
              focalLength.x.isFinite, focalLength.y.isFinite,
              focalLength.x > 0, focalLength.y > 0,
              principalPoint.x.isFinite, principalPoint.y.isFinite else { return nil }

        let cameraPoint = SIMD4<Float>(
            (pixel.x - principalPoint.x) * depth / focalLength.x,
            -(pixel.y - principalPoint.y) * depth / focalLength.y,
            -depth,
            1
        )
        let worldPoint = cameraTransform * cameraPoint
        guard worldPoint.x.isFinite, worldPoint.y.isFinite, worldPoint.z.isFinite else { return nil }
        return SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
    }
}

/// Keeps a bounded, spatially deduplicated record of LiDAR samples on the
/// currently tracked object. Points stay in ARKit world coordinates so the
/// renderer can pin each dot to the surface as the camera moves.
struct GuidedSurfaceCoverage: Sendable {
    static let cellSize: Float = 0.025
    static let maximumPointCount = 360

    private struct Cell: Hashable, Sendable {
        let x: Int
        let y: Int
        let z: Int

        init(_ point: SIMD3<Float>) {
            x = Int(floor(point.x / GuidedSurfaceCoverage.cellSize))
            y = Int(floor(point.y / GuidedSurfaceCoverage.cellSize))
            z = Int(floor(point.z / GuidedSurfaceCoverage.cellSize))
        }
    }

    private(set) var points: [SIMD3<Float>] = []
    private(set) var hapticMilestone = 0
    private var occupiedCells = Set<Cell>()
    private var nextHapticThreshold = 48

    /// Returns true once per meaningful new-surface milestone, never for
    /// repeated depth samples that land in already covered space.
    mutating func insert(_ candidates: [SIMD3<Float>]) -> Bool {
        let previousMilestone = hapticMilestone

        for point in candidates {
            guard point.x.isFinite, point.y.isFinite, point.z.isFinite,
                  abs(point.x) < 10_000, abs(point.y) < 10_000, abs(point.z) < 10_000,
                  points.count < Self.maximumPointCount else { continue }

            let cell = Cell(point)
            guard occupiedCells.insert(cell).inserted else { continue }
            points.append(point)
        }

        if points.count >= nextHapticThreshold {
            hapticMilestone += 1
            nextHapticThreshold += 72
            while points.count >= nextHapticThreshold {
                nextHapticThreshold += 72
            }
        }

        return hapticMilestone != previousMilestone
    }

    mutating func reset() {
        points.removeAll(keepingCapacity: true)
        occupiedCells.removeAll(keepingCapacity: true)
        nextHapticThreshold = 48
        hapticMilestone = 0
    }
}
