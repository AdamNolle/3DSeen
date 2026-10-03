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

/// Tracks spatial coverage at a useful surface resolution while keeping its
/// renderable point cloud bounded through adaptive display sampling.
struct GuidedSurfaceCoverage: Sendable {
    static let cellSize: Float = 0.05
    static let maximumDisplayPointCount = 12_000
    static let maximumTrackedCellCount = 250_000

    private struct Cell: Hashable, Sendable {
        let x: Int
        let y: Int
        let z: Int

        init(_ point: SIMD3<Float>, size: Float) {
            x = Int(floor(point.x / size))
            y = Int(floor(point.y / size))
            z = Int(floor(point.z / size))
        }
    }

    private(set) var points: [SIMD3<Float>] = []
    private(set) var hapticMilestone = 0
    private(set) var uniqueSurfaceCellCount = 0
    private(set) var displayRevision: UInt64 = 0
    private(set) var isAtSampleLimit = false
    private var occupiedCells = Set<Cell>()
    private var displayCells = Set<Cell>()
    private(set) var displayCellSize = Self.cellSize
    private var nextHapticThreshold = 48

    /// Returns true once per new-surface milestone, even when one frame crosses
    /// several thresholds. Samples in previously covered space do not trigger it.
    mutating func insert(_ candidates: [SIMD3<Float>]) -> Bool {
        let previousMilestone = hapticMilestone
        var displayChanged = false

        for point in candidates {
            guard point.x.isFinite, point.y.isFinite, point.z.isFinite,
                  abs(point.x) < 10_000, abs(point.y) < 10_000, abs(point.z) < 10_000 else { continue }

            let coverageCell = Cell(point, size: Self.cellSize)
            guard !occupiedCells.contains(coverageCell) else { continue }
            guard occupiedCells.count < Self.maximumTrackedCellCount else {
                isAtSampleLimit = true
                continue
            }
            occupiedCells.insert(coverageCell)
            uniqueSurfaceCellCount += 1

            var displayCell = Cell(point, size: displayCellSize)
            guard !displayCells.contains(displayCell) else { continue }
            while points.count >= Self.maximumDisplayPointCount {
                guard reduceDisplayResolution() else { break }
                displayChanged = true
                displayCell = Cell(point, size: displayCellSize)
            }
            if points.count < Self.maximumDisplayPointCount,
               displayCells.insert(displayCell).inserted {
                points.append(point)
                displayChanged = true
            }
        }

        while uniqueSurfaceCellCount >= nextHapticThreshold {
            hapticMilestone += 1
            nextHapticThreshold += 72
        }
        if displayChanged {
            displayRevision &+= 1
        }
        return hapticMilestone != previousMilestone
    }

    private mutating func reduceDisplayResolution() -> Bool {
        let nextCellSize = displayCellSize * 2
        guard nextCellSize.isFinite, nextCellSize > displayCellSize else { return false }
        displayCellSize = nextCellSize
        displayCells.removeAll(keepingCapacity: true)
        var reducedPoints: [SIMD3<Float>] = []
        reducedPoints.reserveCapacity(points.count)
        for point in points {
            let cell = Cell(point, size: displayCellSize)
            if displayCells.insert(cell).inserted {
                reducedPoints.append(point)
            }
        }
        points = reducedPoints
        return true
    }

    mutating func reset() {
        points.removeAll(keepingCapacity: true)
        occupiedCells.removeAll(keepingCapacity: true)
        displayCells.removeAll(keepingCapacity: true)
        displayCellSize = Self.cellSize
        uniqueSurfaceCellCount = 0
        displayRevision = 0
        isAtSampleLimit = false
        nextHapticThreshold = 48
        hapticMilestone = 0
    }
}

/// A single indexed mesh keeps RealityKit draw cost independent of point count.
struct GuidedSurfaceDotMesh: Sendable {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let triangleIndices: [UInt32]

    static func build(points: [SIMD3<Float>], radius: Float = 0.0045) -> Self {
        guard radius.isFinite, radius > 0 else {
            return Self(positions: [], normals: [], triangleIndices: [])
        }
        let directions: [SIMD3<Float>] = [
            SIMD3<Float>(radius, 0, 0), SIMD3<Float>(0, radius, 0),
            SIMD3<Float>(-radius, 0, 0), SIMD3<Float>(0, -radius, 0),
            SIMD3<Float>(0, 0, radius), SIMD3<Float>(0, 0, -radius)
        ]
        let triangles: [UInt32] = [
            4, 0, 1, 4, 1, 2, 4, 2, 3, 4, 3, 0,
            5, 1, 0, 5, 2, 1, 5, 3, 2, 5, 0, 3
        ]
        let validPoints = points.filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var triangleIndices: [UInt32] = []
        positions.reserveCapacity(validPoints.count * directions.count)
        normals.reserveCapacity(validPoints.count * directions.count)
        triangleIndices.reserveCapacity(validPoints.count * triangles.count)

        for point in validPoints {
            positions.append(contentsOf: directions.map { point + $0 })
            normals.append(contentsOf: directions.map { simd_normalize($0) })
            let base = UInt32(positions.count - directions.count)
            triangleIndices.append(contentsOf: triangles.map { base + $0 })
        }

        return Self(positions: positions, normals: normals, triangleIndices: triangleIndices)
    }
}

struct GuidedSnapshotPublicationGate: Sendable {
    var minimumInterval: TimeInterval = 0.1
    private(set) var lastPublishedTimestamp = -Double.infinity

    mutating func shouldPublish(at timestamp: TimeInterval) -> Bool {
        guard timestamp.isFinite, timestamp >= lastPublishedTimestamp else { return false }
        guard !lastPublishedTimestamp.isFinite || timestamp - lastPublishedTimestamp >= minimumInterval else {
            return false
        }
        lastPublishedTimestamp = timestamp
        return true
    }

    mutating func reset() {
        lastPublishedTimestamp = -Double.infinity
    }
}
