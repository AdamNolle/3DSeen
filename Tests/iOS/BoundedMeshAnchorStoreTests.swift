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
        XCTAssertTrue(store.update(mesh(triangles: 6), for: firstAnchor))
        XCTAssertTrue(store.update(mesh(triangles: 3), for: secondAnchor))

        XCTAssertFalse(store.update(mesh(triangles: 8), for: firstAnchor))

        XCTAssertEqual(store.triangleCount, 9)
        XCTAssertEqual(store.meshes[firstAnchor]?.triangleCount, 6)
        XCTAssertEqual(store.meshes[secondAnchor]?.triangleCount, 3)
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

    private func mesh(triangles: Int) -> LiDARSurfaceMesh {
        LiDARSurfaceMesh(vertices: [SIMD3<Float>(repeating: 0)], indices: Array(repeating: 0, count: triangles * 3))
    }
}
