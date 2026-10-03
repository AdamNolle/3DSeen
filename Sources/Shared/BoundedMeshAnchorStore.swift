import Foundation

/// Retains the latest accepted mesh per ARKit anchor within the export budget.
/// Rejected updates leave the previous valid geometry available for preview and export.
struct BoundedMeshAnchorStore<AnchorID: Hashable> {
    static var defaultMaximumTriangleCount: Int { 500_000 }

    private(set) var meshes: [AnchorID: LiDARSurfaceMesh] = [:]
    private(set) var triangleCount = 0
    private(set) var didReachLimit = false

    let maximumTriangleCount: Int

    init(maximumTriangleCount: Int = Self.defaultMaximumTriangleCount) {
        self.maximumTriangleCount = max(0, maximumTriangleCount)
    }

    var meshValues: [LiDARSurfaceMesh] {
        Array(meshes.values)
    }

    var isEmpty: Bool {
        meshes.isEmpty
    }

    mutating func canAcceptUpdate(triangleCount newTriangleCount: Int, for anchorID: AnchorID) -> Bool {
        let previousCount = meshes[anchorID]?.triangleCount ?? 0
        let retainedCount = triangleCount - previousCount
        guard newTriangleCount >= 0,
              retainedCount <= maximumTriangleCount,
              newTriangleCount <= maximumTriangleCount - retainedCount else {
            didReachLimit = true
            return false
        }
        return true
    }

    @discardableResult
    mutating func update(_ mesh: LiDARSurfaceMesh, for anchorID: AnchorID) -> Bool {
        guard canAcceptUpdate(triangleCount: mesh.triangleCount, for: anchorID) else { return false }
        let previousCount = meshes[anchorID]?.triangleCount ?? 0
        let retainedCount = triangleCount - previousCount
        meshes[anchorID] = mesh
        triangleCount = retainedCount + mesh.triangleCount
        return true
    }

    mutating func remove(_ anchorID: AnchorID) {
        guard let removed = meshes.removeValue(forKey: anchorID) else { return }
        triangleCount -= removed.triangleCount
    }

    mutating func removeAll(keepingCapacity: Bool = false) {
        meshes.removeAll(keepingCapacity: keepingCapacity)
        triangleCount = 0
        didReachLimit = false
    }
}
