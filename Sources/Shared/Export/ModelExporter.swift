import Foundation
import ModelIO
import RealityKit
import OSLog

/// Universal 3D export formats. ModelIO can write USD/OBJ/STL/PLY natively; glTF and FBX
/// require an external converter (tracked as `requiresConverter`).
public enum ExportFormat: String, CaseIterable {
    case usdz = "USDZ"
    case usd  = "USD"
    case obj  = "OBJ"
    case stl  = "STL"
    case ply  = "PLY"
    case glb  = "glTF"
    case fbx  = "FBX"

    public var fileExtension: String {
        switch self {
        case .usdz: return "usdz"
        case .usd:  return "usdc"
        case .obj:  return "obj"
        case .stl:  return "stl"
        case .ply:  return "ply"
        case .glb:  return "glb"
        case .fbx:  return "fbx"
        }
    }

    /// Whether ModelIO can write this extension directly.
    public var isModelIONative: Bool {
        switch self {
        case .usdz, .usd, .obj, .stl, .ply: return true
        case .glb, .fbx: return false
        }
    }
}

public enum ExportError: LocalizedError {
    case sourceUnreadable(URL)
    case unsupportedByModelIO(String)
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sourceUnreadable(let url): return "Could not read source model at \(url.lastPathComponent)."
        case .unsupportedByModelIO(let ext): return "ModelIO cannot write .\(ext). glTF/FBX need an external converter (planned)."
        case .exportFailed(let msg): return "Export failed: \(msg)"
        }
    }
}

/// Exports completed models to universal 3D formats via ModelIO.
public final class ModelExporter {
    private let logger = Logger(subsystem: "com.adamnolle.3DSeen.Shared", category: "Export")

    public init() {}

    /// Convert a source model (e.g. PhotogrammetrySession's USDZ output) into `format`.
    /// USDZ→USDZ is a straight copy; everything else routes through an `MDLAsset`.
    @discardableResult
    public func export(sourceModel: URL, to format: ExportFormat, outputURL: URL) throws -> URL {
        logger.info("Exporting \(sourceModel.lastPathComponent) → \(format.rawValue) at \(outputURL.path)")
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceModel.path) else { throw ExportError.sourceUnreadable(sourceModel) }

        // Fast path: USDZ → USDZ is a copy.
        if format == .usdz && sourceModel.pathExtension.lowercased() == "usdz" {
            if fm.fileExists(atPath: outputURL.path) { try fm.removeItem(at: outputURL) }
            try fm.copyItem(at: sourceModel, to: outputURL)
            return outputURL
        }

        let asset = MDLAsset(url: sourceModel)
        return try export(asset: asset, to: format, outputURL: outputURL)
    }

    /// Export an in-memory `MDLAsset` to `format`.
    @discardableResult
    public func export(asset: MDLAsset, to format: ExportFormat, outputURL: URL) throws -> URL {
        guard format.isModelIONative else {
            throw ExportError.unsupportedByModelIO(format.fileExtension)
        }
        guard MDLAsset.canExportFileExtension(format.fileExtension) else {
            throw ExportError.unsupportedByModelIO(format.fileExtension)
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) { try fm.removeItem(at: outputURL) }
        do {
            try asset.export(to: outputURL)
        } catch {
            throw ExportError.exportFailed(error.localizedDescription)
        }
        logger.info("Export complete: \(outputURL.lastPathComponent)")
        return outputURL
    }

    /// Builds a demo `MDLAsset` (a smooth sphere) so the export pipeline produces a real file
    /// even before a scan exists. Replace the source with PhotogrammetrySession output in production.
    public func sampleAsset() -> MDLAsset {
        let allocator = MDLMeshBufferDataAllocator()
        let mesh = MDLMesh(
            sphereWithExtent: SIMD3<Float>(0.14, 0.18, 0.14),  // ~ bust-sized, metres
            segments: SIMD2<UInt32>(64, 64),
            inwardNormals: false,
            geometryType: .triangles,
            allocator: allocator
        )
        let asset = MDLAsset(bufferAllocator: allocator)
        asset.add(mesh)
        return asset
    }

    /// Convenience for the UI: write `format` to a temp file from the demo asset and return it.
    public func exportSample(to format: ExportFormat, named base: String = "celestial-bust") throws -> URL {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent(base)
            .appendingPathExtension(format.fileExtension)
        return try export(asset: sampleAsset(), to: format, outputURL: out)
    }
}
