import XCTest
import simd
@testable import ThreeDSeen

final class GuidedSurfaceCoverageTests: XCTestCase {
    func testRoomObjectTracksFollowWorldSpaceInsteadOfFrameLocalVisionLabels() {
        var tracker = RoomObjectTrackRegistry()
        let firstObject = objectPoints(origin: .zero)
        let first = tracker.update(
            observations: [RoomObjectObservation(instanceLabel: 1, points: firstObject)],
            timestamp: 1
        )
        XCTAssertEqual(first.map(\.identifier), [1])

        let shiftedObject = objectPoints(origin: SIMD3<Float>(0.03, 0, 0))
        let sameObject = tracker.update(
            observations: [RoomObjectObservation(instanceLabel: 7, points: shiftedObject)],
            timestamp: 2
        )
        XCTAssertEqual(sameObject.map(\.identifier), [1])

        let nearbyObject = objectPoints(origin: SIMD3<Float>(0.55, 0, 0))
        let twoObjects = tracker.update(
            observations: [
                RoomObjectObservation(instanceLabel: 1, points: shiftedObject),
                RoomObjectObservation(instanceLabel: 2, points: nearbyObject)
            ],
            timestamp: 3
        )
        XCTAssertEqual(Set(twoObjects.map(\.identifier)), [1, 2])
        XCTAssertEqual(tracker.count, 2)

        let revisitedObjects = tracker.update(
            observations: [
                RoomObjectObservation(instanceLabel: 8, points: firstObject),
                RoomObjectObservation(instanceLabel: 9, points: nearbyObject)
            ],
            timestamp: 30
        )
        XCTAssertEqual(Set(revisitedObjects.map(\.identifier)), [1, 2])
        XCTAssertEqual(tracker.count, 2)
    }

    func testRoomObjectTracksReleaseSlotsAfterObjectsHaveBeenAbsent() {
        var tracker = RoomObjectTrackRegistry()
        let observations = (0..<64).map { index in
            RoomObjectObservation(
                instanceLabel: UInt8(index + 1),
                points: objectPoints(origin: SIMD3<Float>(Float(index) * 0.5, 0, 0))
            )
        }

        _ = tracker.update(observations: observations, timestamp: 1)
        XCTAssertEqual(tracker.count, 64)

        _ = tracker.update(observations: [observations[0]], timestamp: 30)
        let newlyDiscovered = RoomObjectObservation(
            instanceLabel: 65,
            points: objectPoints(origin: SIMD3<Float>(40, 0, 0))
        )
        let tracked = tracker.update(observations: [newlyDiscovered], timestamp: 32)

        XCTAssertEqual(tracked.map(\.identifier), [65])
        XCTAssertEqual(tracker.count, 2)
    }

    func testLiveRoomPreviewSeparatesTrackedObjectMeshAndTexture() throws {
        let textureURL = URL(fileURLWithPath: "/tmp/live-object-texture.jpg")
        let camera = LiDARTextureCamera(
            worldToCamera: matrix_identity_float4x4,
            intrinsics: simd_float3x3(columns: (
                SIMD3<Float>(100, 0, 0),
                SIMD3<Float>(0, 100, 0),
                SIMD3<Float>(100, 100, 1)
            )),
            imageWidth: 200,
            imageHeight: 200,
            depthWidth: 4,
            depthHeight: 4,
            depths: [Float](repeating: 2, count: 16)
        )
        let objectMask = LiDARTrackedInstanceMask(
            labels: (0..<16).map { $0 % 4 < 2 ? UInt8(1) : UInt8(0) },
            width: 4,
            height: 4,
            objectIdentifiersByLabel: [1: 47],
            orientation: .landscapeLeft
        )
        let mesh = LiDARSurfaceMesh(
            vertices: [SIMD3(-1.2, -0.5, -2), SIMD3(-0.6, -0.5, -2), SIMD3(-0.9, 0.5, -2)],
            indices: [0, 1, 2]
        )
        let preview = try XCTUnwrap(LiveMeshPreviewBuilder.build(
            meshes: [mesh],
            frames: [LiDARTextureFrame(imageURL: textureURL, camera: camera, objectMask: objectMask)],
            revision: 1,
            isCancelled: { false }
        ))

        XCTAssertEqual(preview.sampledTriangleCount, 1)
        XCTAssertEqual(preview.texturedTriangleCount, 1)
        XCTAssertEqual(preview.batches.map(\.objectIdentifier), [47])
        XCTAssertEqual(preview.batches.first?.textureURL, textureURL)
        XCTAssertEqual(preview.batches.first?.indices.count, 3)
    }

    private func objectPoints(origin: SIMD3<Float>) -> [SIMD3<Float>] {
        (0..<4).flatMap { x in
            (0..<4).map { y in
                origin + SIMD3<Float>(Float(x) * 0.08, Float(y) * 0.08, 0)
            }
        }
    }

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

    func testLiveCoverageHapticsCoalesceRapidSurfaceMilestones() {
        var scheduler = CaptureHapticScheduler(minimumInterval: 1.1)

        XCTAssertEqual(scheduler.nextPulse(at: 1, coverageMilestone: 1), .surfaceCoverage)
        XCTAssertNil(scheduler.nextPulse(at: 1.2, coverageMilestone: 5))
        XCTAssertEqual(scheduler.nextPulse(at: 2.11, coverageMilestone: 5), .surfaceCoverage)
        XCTAssertNil(scheduler.nextPulse(at: 2.2, coverageMilestone: 5))
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
