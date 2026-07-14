// GaussianSplatGenerator.swift — on-device generation of 3D Gaussian Splat radiance fields.
// Converts a captured/derived point cloud into a standard INRIA-format `.ply` (the same format
// Luma/Polycam/KIRI emit) that MetalSplatter renders — entirely offline, no cloud round-trip.
//
// This is the on-device splat *generation/initialization* path: each point becomes an isotropic
// Gaussian with a log-scale, logit-opacity, identity rotation, and SH-DC colour. A future pass can
// add differentiable refinement; the format and pipeline are production-correct today.

import Foundation
import simd
import ModelIO

/// One Gaussian primitive in world space.
public struct Splat {
    public var position: SIMD3<Float>
    public var color: SIMD3<Float>   // linear RGB 0…1
    public var scale: Float          // metres (stored as log)
    public var opacity: Float        // 0…1 (stored as logit)
    public init(position: SIMD3<Float>, color: SIMD3<Float>, scale: Float = 0.02, opacity: Float = 0.9) {
        self.position = position
        self.color = color
        self.scale = scale
        self.opacity = opacity
    }
}

public enum GaussianSplatGenerator {
    /// SH band-0 constant; color = 0.5 + C0 * f_dc.
    static let shC0: Float = 0.28209479177387814

    /// Build splats from a posed point cloud (positions + linear-RGB colours).
    public static func splats(fromPoints points: [(position: SIMD3<Float>, color: SIMD3<Float>)],
                              scale: Float = 0.02, opacity: Float = 0.9) -> [Splat] {
        points.map { Splat(position: $0.position, color: $0.color, scale: scale, opacity: opacity) }
    }

    /// Converts vertices from a real ModelIO asset into a lightweight splat preview. This is a
    /// geometry-derived representation of the computed scan, not a trained neural radiance field.
    public static func splats(fromModelAsset asset: MDLAsset, maximumSplats: Int = 100_000) throws -> [Splat] {
        let meshes = asset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []
        var points: [(position: SIMD3<Float>, color: SIMD3<Float>)] = []

        for mesh in meshes {
            guard let positions = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3) else {
                continue
            }
            let colors = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeColor, as: .float3)
            points.reserveCapacity(points.count + mesh.vertexCount)
            for index in 0..<mesh.vertexCount {
                let position = positions.dataStart
                    .advanced(by: index * positions.stride)
                    .assumingMemoryBound(to: SIMD3<Float>.self)
                    .pointee
                guard position.x.isFinite, position.y.isFinite, position.z.isFinite else { continue }
                let color: SIMD3<Float>
                if let colors {
                    let sampled = colors.dataStart
                        .advanced(by: index * colors.stride)
                        .assumingMemoryBound(to: SIMD3<Float>.self)
                        .pointee
                    color = simd_clamp(sampled, .zero, .one)
                } else {
                    color = SIMD3<Float>(repeating: 0.72)
                }
                points.append((position, color))
            }
        }

        guard !points.isEmpty else { throw SplatGenerationError.noVertexPositions }
        let sampleStride = max(1, Int(ceil(Double(points.count) / Double(max(1, maximumSplats)))))
        return splats(fromPoints: sampleStride == 1 ? points : Swift.stride(from: 0, to: points.count, by: sampleStride).map { points[$0] })
    }

    /// Generates and writes a durable preview PLY from a computed USD/USDZ/OBJ model.
    @discardableResult
    public static func writeModelPreview(from modelURL: URL, to outputURL: URL, maximumSplats: Int = 100_000) throws -> URL {
        let asset = MDLAsset(url: modelURL)
        let splats = try splats(fromModelAsset: asset, maximumSplats: maximumSplats)
        return try SplatPLYWriter.write(splats, to: outputURL)
    }

    #if DEBUG
    /// DEBUG-only deterministic radiance-field fixture for renderer round-trip tests.
    public static func demoCloud(count: Int = 6000, radius: Float = 1.0) -> [Splat] {
        var out: [Splat] = []
        out.reserveCapacity(count)
        let golden = Float.pi * (3 - (5 as Float).squareRoot())
        for i in 0..<count {
            let t = Float(i) / Float(max(1, count - 1))
            let y = 1 - 2 * t
            let r = (max(0, 1 - y * y)).squareRoot()
            let phi = Float(i) * golden
            let p = SIMD3<Float>(cos(phi) * r, y, sin(phi) * r) * radius
            // warm-stone gradient by height + azimuth
            let c = SIMD3<Float>(0.55 + 0.35 * (y * 0.5 + 0.5),
                                 0.42 + 0.20 * r,
                                 0.30 + 0.25 * (sin(phi) * 0.5 + 0.5))
            out.append(Splat(position: p, color: simd_clamp(c, .zero, .one), scale: 0.02, opacity: 0.9))
        }
        return out
    }

    /// Generate splats and write them to a `.ply` in the temp dir; returns the file URL.
    @discardableResult
    public static func writeDemoPLY(named base: String = "3dseen-demo-splat") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(base).appendingPathExtension("ply")
        try SplatPLYWriter.write(demoCloud(), to: url)
        return url
    }
    #endif
}

public enum SplatGenerationError: LocalizedError {
    case noVertexPositions

    public var errorDescription: String? {
        switch self {
        case .noVertexPositions: return "The computed model does not expose vertex positions for a splat preview."
        }
    }
}

/// Writes splats as a standard 3DGS binary-little-endian PLY (x,y,z,f_dc_*,opacity,scale_*,rot_*).
public enum SplatPLYWriter {
    private static func logit(_ a: Float) -> Float {
        let clamped = min(max(a, 1e-4), 1 - 1e-4)
        return log(clamped / (1 - clamped))
    }

    @discardableResult
    public static func write(_ splats: [Splat], to url: URL) throws -> URL {
        let header = """
        ply
        format binary_little_endian 1.0
        element vertex \(splats.count)
        property float x
        property float y
        property float z
        property float nx
        property float ny
        property float nz
        property float f_dc_0
        property float f_dc_1
        property float f_dc_2
        property float opacity
        property float scale_0
        property float scale_1
        property float scale_2
        property float rot_0
        property float rot_1
        property float rot_2
        property float rot_3
        end_header

        """
        var data = Data(header.utf8)
        data.reserveCapacity(header.count + splats.count * 17 * 4)

        func appendFloat(_ value: Float) {
            var le = value.bitPattern.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        let c0 = GaussianSplatGenerator.shC0
        for s in splats {
            // position
            appendFloat(s.position.x); appendFloat(s.position.y); appendFloat(s.position.z)
            // normals (unused by the splat renderer but required in the header property set)
            appendFloat(0); appendFloat(0); appendFloat(0)
            // colour → SH DC
            appendFloat((s.color.x - 0.5) / c0)
            appendFloat((s.color.y - 0.5) / c0)
            appendFloat((s.color.z - 0.5) / c0)
            // opacity (logit) + scale (log), isotropic
            appendFloat(logit(s.opacity))
            let logScale = log(max(s.scale, 1e-5))
            appendFloat(logScale); appendFloat(logScale); appendFloat(logScale)
            // rotation quaternion (identity: w,x,y,z)
            appendFloat(1); appendFloat(0); appendFloat(0); appendFloat(0)
        }

        try data.write(to: url)
        return url
    }
}
