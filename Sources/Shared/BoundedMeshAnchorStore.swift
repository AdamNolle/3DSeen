import Foundation

/// Retains the latest accepted mesh per ARKit anchor within the export budget.
/// Rejected updates leave the previous valid geometry available for preview and export.
struct BoundedMeshAnchorStore<AnchorID: Hashable> {
    static var defaultMaximumTriangleCount: Int { 500_000 }

    private(set) var meshes: [AnchorID: LiDARSurfaceMesh] = [:]
    private(set) var triangleCount = 0
    private(set) var classificationCounts: [UInt8: Int] = [:]
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
        let previousMesh = meshes[anchorID]
        let previousCount = previousMesh?.triangleCount ?? 0
        let retainedCount = triangleCount - previousCount
        if let previousMesh { adjustClassifications(previousMesh.classifications, by: -1) }
        meshes[anchorID] = mesh
        adjustClassifications(mesh.classifications, by: 1)
        triangleCount = retainedCount + mesh.triangleCount
        return true
    }

    mutating func remove(_ anchorID: AnchorID) {
        guard let removed = meshes.removeValue(forKey: anchorID) else { return }
        adjustClassifications(removed.classifications, by: -1)
        triangleCount -= removed.triangleCount
    }

    mutating func removeAll(keepingCapacity: Bool = false) {
        meshes.removeAll(keepingCapacity: keepingCapacity)
        triangleCount = 0
        classificationCounts.removeAll(keepingCapacity: keepingCapacity)
        didReachLimit = false
    }

    private mutating func adjustClassifications(_ values: [UInt8], by delta: Int) {
        for value in values where value != 0 {
            let updatedCount = (classificationCounts[value] ?? 0) + delta
            if updatedCount > 0 {
                classificationCounts[value] = updatedCount
            } else {
                classificationCounts[value] = nil
            }
        }
    }
}
