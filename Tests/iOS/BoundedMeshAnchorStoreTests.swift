import XCTest
@testable import ThreeDSeen

final class BoundedMeshAnchorStoreTests: XCTestCase {
    func testAnchorReplacementKeepsAggregateCountAccurate() {
        var store = BoundedMeshAnchorStore<UUID>(maximumTriangleCount: 10)
        let anchorID = UUID()

        XCTAssertTrue(store.update(mesh(triangles: 6), for: anchorID))
        XCTAssertTrue(store.update(mesh(triangles: 9), for: anchorID))

        XCTAssertEqual(store.triangleCount, 9)
        XCTAssertEqual(store.meshes[anchorID]?.triangleCount, 9)
        XCTAssertFalse(store.didReachLimit)
    }

    func testOverBudgetNewAnchorLeavesExistingGeometryIntact() {
        var store = BoundedMeshAnchorStore<UUID>(maximumTriangleCount: 10)
        let acceptedAnchor = UUID()
        let rejectedAnchor = UUID()
        XCTAssertTrue(store.update(mesh(triangles: 8), for: acceptedAnchor))

        XCTAssertFalse(store.update(mesh(triangles: 3), for: rejectedAnchor))

        XCTAssertEqual(store.triangleCount, 8)
        XCTAssertEqual(store.meshes[acceptedAnchor]?.triangleCount, 8)
        XCTAssertNil(store.meshes[rejectedAnchor])
        XCTAssertTrue(store.didReachLimit)
    }

    func testRejectedAnchorReplacementKeepsLastAcceptedMesh() {
        var store = BoundedMeshAnchorStore<UUID>(maximumTriangleCount: 10)
        let firstAnchor = UUID()
        let secondAnchor = UUID()
        XCTAssertTrue(store.update(mesh(triangles: 6, classifications: Array(repeating: 1, count: 6)), for: firstAnchor))
        XCTAssertTrue(store.update(mesh(triangles: 3, classifications: Array(repeating: 2, count: 3)), for: secondAnchor))

        XCTAssertFalse(store.update(mesh(triangles: 8, classifications: Array(repeating: 3, count: 8)), for: firstAnchor))

        XCTAssertEqual(store.triangleCount, 9)
        XCTAssertEqual(store.meshes[firstAnchor]?.triangleCount, 6)
        XCTAssertEqual(store.meshes[secondAnchor]?.triangleCount, 3)
        XCTAssertEqual(store.classificationCounts[1], 6)
        XCTAssertEqual(store.classificationCounts[2], 3)
        XCTAssertNil(store.classificationCounts[3])
        XCTAssertTrue(store.didReachLimit)
    }

    func testRemovingAnchorFreesCapacityForNewGeometry() {
        var store = BoundedMeshAnchorStore<UUID>(maximumTriangleCount: 10)
        let removedAnchor = UUID()
        let retainedAnchor = UUID()
        let newAnchor = UUID()
        XCTAssertTrue(store.update(mesh(triangles: 6), for: removedAnchor))
        XCTAssertTrue(store.update(mesh(triangles: 4), for: retainedAnchor))

        store.remove(removedAnchor)

        XCTAssertTrue(store.update(mesh(triangles: 6), for: newAnchor))
        XCTAssertEqual(store.triangleCount, 10)
        XCTAssertFalse(store.isEmpty)
    }

    func testClassificationCountsTrackAnchorReplacementAndRemoval() {
        var store = BoundedMeshAnchorStore<UUID>(maximumTriangleCount: 10)
        let firstAnchor = UUID()
        let secondAnchor = UUID()

        XCTAssertTrue(store.update(mesh(triangles: 2, classifications: [1, 1]), for: firstAnchor))
        XCTAssertTrue(store.update(mesh(triangles: 3, classifications: [2, 2, 2]), for: secondAnchor))
        XCTAssertTrue(store.update(mesh(triangles: 1, classifications: [2]), for: firstAnchor))

        XCTAssertNil(store.classificationCounts[1])
        XCTAssertEqual(store.classificationCounts[2], 4)

        store.remove(secondAnchor)

        XCTAssertEqual(store.classificationCounts[2], 1)
    }

    private func mesh(triangles: Int, classifications: [UInt8] = []) -> LiDARSurfaceMesh {
        LiDARSurfaceMesh(
            vertices: [SIMD3<Float>(repeating: 0)],
            indices: Array(repeating: 0, count: triangles * 3),
            classifications: classifications
        )
    }
}
