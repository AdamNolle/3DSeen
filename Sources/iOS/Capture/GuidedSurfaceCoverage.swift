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

    struct GridConfiguration: Sendable {
        let depthSize: SIMD2<Int>
        let imageSize: SIMD2<Int>
        let sampleStep: Int
        let focalLength: SIMD2<Float>
        let principalPoint: SIMD2<Float>
        let cameraTransform: simd_float4x4
        var minimumConfidence: UInt8 = 1
        var maximumDepth: Float = 8
    }

    /// Converts a regularly sampled depth grid into world-space surface points.
    /// The captured-image dimensions keep intrinsics and depth pixels aligned.
    static func sampledWorldPositions(
        depths: [Float],
        confidenceValues: [UInt8]? = nil,
        configuration: GridConfiguration
    ) -> [SIMD3<Float>] {
        let depthWidth = configuration.depthSize.x
        let depthHeight = configuration.depthSize.y
        let imageWidth = configuration.imageSize.x
        let imageHeight = configuration.imageSize.y
        let sampleStep = configuration.sampleStep
        let depthDimensionsAreSafe = depthWidth > 0
            && depthHeight > 0
            && depthWidth <= Int.max / depthHeight
        let depthElementCount = depthDimensionsAreSafe ? depthWidth * depthHeight : 0
        let hasValidConfidenceMap = confidenceValues.map { $0.count >= depthElementCount } ?? true
        guard depthDimensionsAreSafe,
              imageWidth > 0, imageHeight > 0,
              sampleStep > 0,
              depths.count >= depthElementCount,
              hasValidConfidenceMap,
              configuration.maximumDepth.isFinite, configuration.maximumDepth > 0 else { return [] }

        var points: [SIMD3<Float>] = []
        let start = sampleStep / 2
        for y in stride(from: start, to: depthHeight, by: sampleStep) {
            for x in stride(from: start, to: depthWidth, by: sampleStep) {
                let sampleIndex = (y * depthWidth) + x
                if let confidenceValues,
                   confidenceValues[sampleIndex] < configuration.minimumConfidence {
                    continue
                }
                let depth = depths[sampleIndex]
                guard depth <= configuration.maximumDepth else { continue }
                let pixel = SIMD2<Float>(
                    (Float(x) + 0.5) * Float(imageWidth) / Float(depthWidth),
                    (Float(y) + 0.5) * Float(imageHeight) / Float(depthHeight)
                )
                if let point = worldPosition(
                    pixel: pixel,
                    depth: depth,
                    focalLength: configuration.focalLength,
                    principalPoint: configuration.principalPoint,
                    cameraTransform: configuration.cameraTransform
                ) {
                    points.append(point)
                }
            }
        }
        return points
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
    private let firstHapticThreshold: Int
    private let hapticInterval: Int
    private var nextHapticThreshold: Int

    init(firstHapticThreshold: Int = 48, hapticInterval: Int = 72) {
        self.firstHapticThreshold = max(1, firstHapticThreshold)
        self.hapticInterval = max(1, hapticInterval)
        nextHapticThreshold = max(1, firstHapticThreshold)
    }

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
            nextHapticThreshold += hapticInterval
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
        nextHapticThreshold = firstHapticThreshold
        hapticMilestone = 0
    }
}

/// Coalesces room-coverage milestones and object discoveries into one tactile event stream.
/// Pending events survive rate limiting so fast coverage updates are not silently discarded.
enum CaptureHapticKind: Equatable, Sendable {
    case surfaceCoverage
    case objectDiscovery
}

struct CaptureHapticScheduler: Sendable {
    private let minimumInterval: TimeInterval
    private var lastCoverageMilestone = 0
    private var lastPulseTimestamp = -Double.infinity
    private var hasPendingCoveragePulse = false
    private var hasPendingObjectPulse = false

    init(minimumInterval: TimeInterval = 1.1) {
        self.minimumInterval = max(0, minimumInterval)
    }

    mutating func nextPulse(
        at timestamp: TimeInterval,
        coverageMilestone: Int,
        objectWasDiscovered: Bool = false
    ) -> CaptureHapticKind? {
        guard timestamp.isFinite else { return nil }
        if coverageMilestone > lastCoverageMilestone {
            hasPendingCoveragePulse = true
        }
        hasPendingObjectPulse = hasPendingObjectPulse || objectWasDiscovered
        guard hasPendingCoveragePulse || hasPendingObjectPulse,
              timestamp - lastPulseTimestamp >= minimumInterval else { return nil }

        lastCoverageMilestone = max(lastCoverageMilestone, coverageMilestone)
        lastPulseTimestamp = timestamp
        let kind: CaptureHapticKind = hasPendingObjectPulse ? .objectDiscovery : .surfaceCoverage
        hasPendingCoveragePulse = false
        hasPendingObjectPulse = false
        return kind
    }
}

/// One camera-view object hypothesis backed by measured LiDAR points.
struct RoomObjectObservation: Sendable {
    let instanceLabel: UInt8
    let points: [SIMD3<Float>]
}

struct RoomObjectFrameDetection: Sendable {
    let observations: [RoomObjectObservation]
    let instanceMask: LiDARTrackedInstanceMask
}

struct TrackedRoomObject: Sendable {
    let identifier: Int
    let instanceLabel: UInt8
    let points: [SIMD3<Float>]
}

/// Associates Vision's frame-local instance labels through their world-space LiDAR samples.
/// Labels from Vision are intentionally never treated as persistent object identities.
struct RoomObjectTrackRegistry: Sendable {
    private struct Cell: Hashable, Sendable {
        let x: Int
        let y: Int
        let z: Int

        init(_ point: SIMD3<Float>) {
            x = Int(floor(point.x / Self.size))
            y = Int(floor(point.y / Self.size))
            z = Int(floor(point.z / Self.size))
        }

        private static let size: Float = 0.12
    }

    private struct Track: Sendable {
        let identifier: Int
        var center: SIMD3<Float>
        var cells: Set<Cell>
        var lastSeen: TimeInterval
    }

    private(set) var count = 0
    private var tracks: [Track] = []
    private var nextIdentifier = 1

    private static let maximumTrackCount = 64
    private static let maximumCellsPerTrack = 2_048
    private static let maximumAssociationDistance: Float = 0.30
    private static let trackRetentionInterval: TimeInterval = 30

    mutating func update(
        observations: [RoomObjectObservation],
        timestamp: TimeInterval
    ) -> [TrackedRoomObject] {
        guard timestamp.isFinite else { return [] }
        tracks.removeAll { track in
            timestamp > track.lastSeen && timestamp - track.lastSeen > Self.trackRetentionInterval
        }
        var matched = Set<Int>()
        var output: [TrackedRoomObject] = []

        for observation in observations.sorted(by: { $0.points.count > $1.points.count }) {
            let points = observation.points.filter(Self.isValid)
            guard points.count >= 12 else { continue }
            let center = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
            let observationCells = Set(points.map(Cell.init))
            let match = tracks.indices
                .filter { !matched.contains($0) }
                .compactMap { index -> (Int, Int, Float)? in
                    let track = tracks[index]
                    let overlap = observationCells.intersection(track.cells).count
                    let distance = simd_distance(center, track.center)
                    guard overlap >= 3 || distance <= Self.maximumAssociationDistance else { return nil }
                    return (index, overlap, distance)
                }
                .min { lhs, rhs in
                    lhs.1 == rhs.1 ? lhs.2 < rhs.2 : lhs.1 > rhs.1
                }?.0

            let trackIndex: Int
            if let match {
                trackIndex = match
                matched.insert(match)
                tracks[match].lastSeen = timestamp
                tracks[match].center = tracks[match].center * 0.65 + center * 0.35
                for cell in observationCells where tracks[match].cells.count < Self.maximumCellsPerTrack {
                    tracks[match].cells.insert(cell)
                }
            } else {
                guard tracks.count < Self.maximumTrackCount else { continue }
                trackIndex = tracks.count
                let identifier = nextIdentifier
                nextIdentifier += 1
                tracks.append(Track(
                    identifier: identifier,
                    center: center,
                    cells: Set(observationCells.prefix(Self.maximumCellsPerTrack)),
                    lastSeen: timestamp
                ))
                matched.insert(trackIndex)
            }
            output.append(TrackedRoomObject(
                identifier: tracks[trackIndex].identifier,
                instanceLabel: observation.instanceLabel,
                points: points
            ))
        }

        count = tracks.count
        return output
    }

    private static func isValid(_ point: SIMD3<Float>) -> Bool {
        point.x.isFinite && point.y.isFinite && point.z.isFinite
            && abs(point.x) < 10_000 && abs(point.y) < 10_000 && abs(point.z) < 10_000
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
