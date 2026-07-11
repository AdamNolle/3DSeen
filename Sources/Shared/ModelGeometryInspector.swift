import Foundation
import ModelIO

/// Geometry facts derived from an actual ModelIO asset. The formatted count is display-only; the
/// integer values remain available to callers that need accurate downstream metadata.
public struct ModelGeometryFacts: Equatable, Sendable {
    public let vertexCount: Int
    public let triangleCount: Int

    public init(vertexCount: Int, triangleCount: Int) {
        self.vertexCount = max(0, vertexCount)
        self.triangleCount = max(0, triangleCount)
    }

    public var formattedTriangleCount: String {
        switch triangleCount {
        case 1_000_000...:
            return String(format: "%.1fM", Double(triangleCount) / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", Double(triangleCount) / 1_000)
        default:
            return "\(triangleCount)"
        }
    }
}

/// Reads mesh topology from a completed model so viewer metadata is derived from the file rather
/// than guessed during capture.
public enum ModelGeometryInspector {
    public static func inspect(modelURL: URL) -> ModelGeometryFacts? {
        inspect(asset: MDLAsset(url: modelURL))
    }

    public static func inspect(asset: MDLAsset) -> ModelGeometryFacts? {
        let meshes = asset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []
        var vertexCount = 0
        var triangleCount = 0

        for mesh in meshes {
            vertexCount += mesh.vertexCount
            let submeshes = mesh.submeshes as? [MDLSubmesh] ?? []
            for submesh in submeshes {
                switch submesh.geometryType {
                case .triangles:
                    triangleCount += submesh.indexCount / 3
                case .triangleStrips:
                    triangleCount += max(0, submesh.indexCount - 2)
                default:
                    break
                }
            }
        }

        guard vertexCount > 0 else { return nil }
        return ModelGeometryFacts(vertexCount: vertexCount, triangleCount: triangleCount)
    }
}
