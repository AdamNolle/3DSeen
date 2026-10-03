import XCTest
import simd
@testable import ThreeDSeen

final class GuidedSurfaceCoverageTests: XCTestCase {
    func testDepthGridSamplingProjectsValidSurfacePointsIntoWorldSpace() {
        var depths = Array(repeating: Float(2), count: 16)
        depths[7] = .nan
        depths[13] = 0
        depths[15] = 4
        var confidence = Array(repeating: UInt8(2), count: 16)
        confidence[15] = 0
        var cameraTransform = matrix_identity_float4x4
        cameraTransform.columns.3 = SIMD4<Float>(1, 0, 0, 1)

        let points = GuidedDepthProjection.sampledWorldPositions(
            depths: depths,
            confidenceValues: confidence,
            configuration: GuidedDepthProjection.GridConfiguration(
                depthSize: SIMD2<Int>(4, 4),
                imageSize: SIMD2<Int>(4, 4),
                sampleStep: 2,
                focalLength: SIMD2<Float>(2, 2),
                principalPoint: SIMD2<Float>(2, 2),
                cameraTransform: cameraTransform
            )
        )

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0], SIMD3<Float>(0.5, 0.5, -2))
    }

    func testDepthProjectionMapsPixelAndCameraOriginIntoWorldSpace() throws {
        var cameraTransform = matrix_identity_float4x4
        cameraTransform.columns.3 = SIMD4<Float>(1, 2, 3, 1)

        let centerPoint = try XCTUnwrap(GuidedDepthProjection.worldPosition(
            pixel: SIMD2<Float>(640, 480),
            depth: 2,
            focalLength: SIMD2<Float>(800, 800),
            principalPoint: SIMD2<Float>(640, 480),
            cameraTransform: cameraTransform
        ))
        XCTAssertEqual(centerPoint, SIMD3<Float>(1, 2, 1))

        let rightAndDownPoint = try XCTUnwrap(GuidedDepthProjection.worldPosition(
            pixel: SIMD2<Float>(720, 560),
            depth: 2,
            focalLength: SIMD2<Float>(800, 800),
            principalPoint: SIMD2<Float>(640, 480),
            cameraTransform: matrix_identity_float4x4
        ))
        XCTAssertEqual(rightAndDownPoint, SIMD3<Float>(0.2, -0.2, -2))
    }

    func testCoverageDeduplicatesNearbyLiDARSamples() {
        var coverage = GuidedSurfaceCoverage()
        let point = SIMD3<Float>(0.12, 0.24, -0.38)

        XCTAssertFalse(coverage.insert([point]))
        XCTAssertFalse(coverage.insert([point + SIMD3<Float>(0.004, 0.003, -0.002)]))
        XCTAssertEqual(coverage.points.count, 1)
    }

    func testCoverageEmitsOneHapticForNewSurfaceMilestone() {
        var coverage = GuidedSurfaceCoverage()
        let points = (0..<48).map { index in
            SIMD3<Float>(Float(index) * GuidedSurfaceCoverage.cellSize, 0, 0)
        }

        XCTAssertTrue(coverage.insert(points))
        XCTAssertEqual(coverage.hapticMilestone, 1)
        XCTAssertFalse(coverage.insert(points))
        XCTAssertEqual(coverage.hapticMilestone, 1)
    }

    func testCoverageCanUseRoomScaleHapticMilestones() {
        var coverage = GuidedSurfaceCoverage(firstHapticThreshold: 200, hapticInterval: 400)
        let points = (0..<600).map { index in
            SIMD3<Float>(Float(index) * GuidedSurfaceCoverage.cellSize + 0.01, 0, 0)
        }

        XCTAssertFalse(coverage.insert(Array(points.prefix(199))))
        XCTAssertTrue(coverage.insert([points[199]]))
        XCTAssertEqual(coverage.hapticMilestone, 1)
        XCTAssertFalse(coverage.insert(Array(points[200..<599])))
        XCTAssertTrue(coverage.insert([points[599]]))
        XCTAssertEqual(coverage.hapticMilestone, 2)
    }

    func testCoverageKeepsDiscoveringAndPinningSurfaceBeyond360Samples() {
        var coverage = GuidedSurfaceCoverage()
        let points = (0..<432).map { index in
            SIMD3<Float>(Float(index) * GuidedSurfaceCoverage.cellSize, 0, 0)
        }

        _ = coverage.insert(Array(points.prefix(360)))
        let firstSideMilestone = coverage.hapticMilestone
        _ = coverage.insert(Array(points.dropFirst(360)))

        XCTAssertEqual(coverage.points.count, 432)
        XCTAssertEqual(coverage.points.last, points.last)
        XCTAssertGreaterThan(coverage.hapticMilestone, firstSideMilestone)
    }

    func testCoverageCanResetForAnotherScan() {
        var coverage = GuidedSurfaceCoverage()
        let points = (0..<500).map { index in
            SIMD3<Float>(Float(index) * GuidedSurfaceCoverage.cellSize, 0, 0)
        }

        _ = coverage.insert(points)
        XCTAssertEqual(coverage.points.count, 500)
        XCTAssertEqual(coverage.uniqueSurfaceCellCount, 500)

        coverage.reset()
        XCTAssertTrue(coverage.points.isEmpty)
        XCTAssertEqual(coverage.uniqueSurfaceCellCount, 0)
        XCTAssertEqual(coverage.hapticMilestone, 0)
    }

    func testCoverageAdaptsDisplayDensityWithoutStoppingSurfaceDiscovery() {
        var coverage = GuidedSurfaceCoverage()
        let points = (0..<(GuidedSurfaceCoverage.maximumDisplayPointCount + 3_000)).map { index in
            SIMD3<Float>(Float(index) * GuidedSurfaceCoverage.cellSize, 0, 0)
        }

        _ = coverage.insert(points)

        XCTAssertEqual(coverage.uniqueSurfaceCellCount, points.count)
        XCTAssertLessThanOrEqual(coverage.points.count, GuidedSurfaceCoverage.maximumDisplayPointCount)
        let lastSample = SIMD3<Float>(Float(points.count - 1) * GuidedSurfaceCoverage.cellSize, 0, 0)
        let distanceToLastSample = coverage.points.map { simd_distance($0, lastSample) }.min() ?? .infinity
        XCTAssertLessThanOrEqual(distanceToLastSample, coverage.displayCellSize * 1.75)
        XCTAssertGreaterThan(coverage.displayRevision, 0)
        XCTAssertGreaterThan(coverage.hapticMilestone, 0)
    }

    func testBatchedSurfaceDotMeshUsesOneMarkerPerPoint() {
        let mesh = GuidedSurfaceDotMesh.build(points: [.zero, SIMD3<Float>(1, 2, 3)])

        XCTAssertEqual(mesh.positions.count, 12)
        XCTAssertEqual(mesh.normals.count, 12)
        XCTAssertEqual(mesh.triangleIndices.count, 48)
        XCTAssertEqual(mesh.triangleIndices.max(), 11)
    }

    func testCoverageSkipsNonFiniteAndOutOfRangeWorldPoints() {
        var coverage = GuidedSurfaceCoverage()

        _ = coverage.insert([
            SIMD3<Float>(.nan, 0, 0),
            SIMD3<Float>(Float.greatestFiniteMagnitude, 0, 0)
        ])

        XCTAssertTrue(coverage.points.isEmpty)
    }

    func testDepthProjectionRejectsInvalidSamples() {
        XCTAssertNil(GuidedDepthProjection.worldPosition(
            pixel: .zero,
            depth: .nan,
            focalLength: SIMD2<Float>(800, 800),
            principalPoint: .zero,
            cameraTransform: matrix_identity_float4x4
        ))
    }
}
