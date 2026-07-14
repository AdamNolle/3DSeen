import Foundation
import ModelIO
import RealityKit
import OSLog
import ZIPFoundation

/// Universal 3D export formats. USDZ is retained as a lossless pass-through when it is the
/// computed source; ModelIO writes USD/OBJ/STL/PLY, while GLB and FBX require Blender.
public enum ExportFormat: String, CaseIterable, Sendable {
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

    /// Whether the built-in exporter handles this format without an external converter.
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
    case noSourceAsset(UUID)

    public var errorDescription: String? {
        switch self {
        case .sourceUnreadable(let url): return "Could not read source model at \(url.lastPathComponent)."
        case .unsupportedByModelIO(let ext): return "ModelIO cannot write .\(ext). glTF/FBX require an external converter."
        case .exportFailed(let msg): return "Export failed: \(msg)"
        case .noSourceAsset(let scanID): return "Scan \(scanID.uuidString) does not have a computed model to export."
        }
    }
}

/// Exports completed models to universal 3D formats via ModelIO.
public struct ScanResultPackage {
    public struct Contents {
        public let manifest: ScanAssetManifest
        public let modelURL: URL
        public let previewPLYURL: URL?
    }

    public static let fileSuffix = ".3dseen-result.zip"
    private static let modelExtensions = Set(["usdz", "obj", "stl"])

    public init() {}

    public func write(output: URL, manifest: ScanAssetManifest) throws -> URL {
        let fm = FileManager.default
        let packageID = UUID().uuidString
        let packageDir = fm.temporaryDirectory.appendingPathComponent("3dseen-result-\(packageID)", isDirectory: true)
        let zipURL = fm.temporaryDirectory.appendingPathComponent("3dseen-result-\(packageID)\(Self.fileSuffix)")
        try fm.createDirectory(at: packageDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: packageDir) }

        let modelURL = packageDir.appendingPathComponent(output.lastPathComponent)
        if fm.fileExists(atPath: modelURL.path) {
            try fm.removeItem(at: modelURL)
        }
        try fm.copyItem(at: output, to: modelURL)

        if let previewPLYURL = manifest.previewPLYURL,
           previewPLYURL != output,
           fm.fileExists(atPath: previewPLYURL.path) {
            let payloadKind: PLYPayloadKind = manifest.previewPLYKind == .trainedSplat
                ? .trainedSplat
                : .geometry
            guard PLYValidator.isValid(previewPLYURL, kind: payloadKind) else {
                throw ExportError.sourceUnreadable(previewPLYURL)
            }
            let previewName = manifest.previewPLYKind == .trainedSplat ? "trained-splat.ply" : "geometry-preview.ply"
            let previewURL = packageDir.appendingPathComponent(previewName)
            try fm.copyItem(at: previewPLYURL, to: previewURL)
        }

        let manifestURL = packageDir.appendingPathComponent("manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)

        if fm.fileExists(atPath: zipURL.path) {
            try fm.removeItem(at: zipURL)
        }
        try fm.zipItem(at: packageDir, to: zipURL, shouldKeepParent: false)
        return zipURL
    }

    public func unpack(_ packageURL: URL, to destination: URL) throws -> Contents {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        try fm.unzipItem(at: packageURL, to: destination)
        let files = try fm.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
        guard let manifestURL = files.first(where: { $0.lastPathComponent == "manifest.json" }) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        guard let modelURL = files.first(where: { Self.modelExtensions.contains($0.pathExtension.lowercased()) }) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        guard let size = try? modelURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0,
              ModelGeometryInspector.inspect(modelURL: modelURL) != nil else {
            throw ExportError.sourceUnreadable(modelURL)
        }
        let manifest = try JSONDecoder().decode(ScanAssetManifest.self, from: Data(contentsOf: manifestURL))
        let previewPLYURL = files.first { $0.pathExtension.lowercased() == "ply" }
        if let previewPLYURL {
            let payloadKind: PLYPayloadKind = manifest.previewPLYKind == .trainedSplat
                ? .trainedSplat
                : .geometry
            guard PLYValidator.isValid(previewPLYURL, kind: payloadKind) else {
                throw ExportError.sourceUnreadable(previewPLYURL)
            }
        }
        return Contents(manifest: manifest, modelURL: modelURL, previewPLYURL: previewPLYURL)
    }
}

/// Writes user-created model distances in a portable CSV companion file.
public struct MeasurementExporter {
    public init() {}

    @discardableResult
    public func exportCSV(_ measurements: [ScanMeasurement], named baseName: String, to directory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let sanitized = baseName.isEmpty ? "scan" : baseName
        let output = directory.appendingPathComponent("\(sanitized)-measurements.csv")
        let header = "label,meters,centimeters,inches,start_x,start_y,start_z,end_x,end_y,end_z\n"
        let rows = measurements.map { measurement in
            let label = csvField(measurement.label)
            return String(
                format: "%@,%.6f,%.3f,%.3f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f",
                label,
                measurement.meters,
                measurement.meters * 100,
                measurement.meters * 39.37007874,
                measurement.start.x, measurement.start.y, measurement.start.z,
                measurement.end.x, measurement.end.y, measurement.end.z
            )
        }
        try (header + rows.joined(separator: "\n") + (rows.isEmpty ? "" : "\n"))
            .data(using: .utf8)?.write(to: output, options: .atomic)
        return output
    }

    private func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

public struct ModelExportRequest: Sendable {
    public let scanID: UUID
    public let sourceModelURL: URL
    public let fileBaseName: String
    public let measurements: [ScanMeasurement]

    public init(scanID: UUID, sourceModelURL: URL, fileBaseName: String, measurements: [ScanMeasurement]) {
        self.scanID = scanID
        self.sourceModelURL = sourceModelURL
        self.fileBaseName = fileBaseName
        self.measurements = measurements
    }
}

public enum ScanExportLocation {
    public static func rootDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("3DSeen/Exports", isDirectory: true)
    }

    public static func directory(for scanID: UUID, fileManager: FileManager = .default) -> URL {
        rootDirectory(fileManager: fileManager).appendingPathComponent(scanID.uuidString, isDirectory: true)
    }
}

@MainActor
public enum ScanExportProvenanceRecorder {
    public static func record(
        _ outputURL: URL,
        on scan: ScanSession,
        assetStore: ScanAssetStore,
        save: () throws -> Void
    ) throws {
        let previousURL = scan.lastExportedURL
        let previousName = scan.lastExportedFileName
        let previousDate = scan.lastExportedAt
        scan.lastExportedURL = outputURL
        scan.lastExportedFileName = outputURL.lastPathComponent
        scan.lastExportedAt = Date()
        do {
            try assetStore.writeManifest(try assetStore.manifest(for: scan))
            try save()
        } catch {
            scan.lastExportedURL = previousURL
            scan.lastExportedFileName = previousName
            scan.lastExportedAt = previousDate
            try? assetStore.writeManifest(try assetStore.manifest(for: scan))
            throw error
        }
    }
}

public final class ModelExporter {
    private let logger = Logger(subsystem: "com.adamnolle.3DSeen.Shared", category: "Export")

    public init() {}

    @discardableResult
    public func export(
        request: ModelExportRequest,
        to format: ExportFormat,
        outputDirectory: URL? = nil
    ) throws -> URL {
        let directory = outputDirectory ?? ScanExportLocation.directory(for: request.scanID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory
            .appendingPathComponent(request.fileBaseName)
            .appendingPathExtension(format.fileExtension)
        return try export(sourceModel: request.sourceModelURL, to: format, outputURL: outputURL)
    }

    /// Export the best available model attached to a scan session and remember the exported file URL.
    @discardableResult
    public func export(session: ScanSession, to format: ExportFormat, outputDirectory: URL? = nil) throws -> URL {
        guard let source = session.displayModelURL else {
            throw ExportError.noSourceAsset(session.id)
        }

        let request = ModelExportRequest(
            scanID: session.id,
            sourceModelURL: source,
            fileBaseName: session.exportFileBaseName,
            measurements: session.measurements
        )
        let exported = try export(request: request, to: format, outputDirectory: outputDirectory)
        session.lastExportedURL = exported
        session.lastExportedFileName = exported.lastPathComponent
        session.lastExportedAt = Date()
        return exported
    }

    /// Convert a source model (e.g. PhotogrammetrySession's USDZ output) into `format`.
    /// USDZ→USDZ is a straight copy; everything else routes through an `MDLAsset`.
    @discardableResult
    public func export(sourceModel: URL, to format: ExportFormat, outputURL: URL) throws -> URL {
        logger.info("Exporting \(sourceModel.lastPathComponent) → \(format.rawValue) at \(outputURL.path)")
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceModel.path) else { throw ExportError.sourceUnreadable(sourceModel) }

        // Fast path: USDZ → USDZ is a transactional copy.
        if format == .usdz && sourceModel.pathExtension.lowercased() == "usdz" {
            guard sourceModel.standardizedFileURL != outputURL.standardizedFileURL else { return outputURL }
            let staging = stagingURL(for: outputURL)
            defer { try? fm.removeItem(at: staging) }
            try fm.copyItem(at: sourceModel, to: staging)
            try commit(staging, to: outputURL)
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
        let stagingDirectory = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".pending-export-\(UUID().uuidString)", isDirectory: true)
        let staging = stagingDirectory.appendingPathComponent(outputURL.lastPathComponent)
        defer { try? fm.removeItem(at: stagingDirectory) }
        do {
            try fm.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            try asset.export(to: staging)
            guard let size = try? staging.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
                throw ExportError.exportFailed("The exporter produced an empty file.")
            }
            try commitExportDirectory(stagingDirectory, primary: staging, to: outputURL)
        } catch let error as ExportError {
            throw error
        } catch {
            throw ExportError.exportFailed(error.localizedDescription)
        }
        logger.info("Export complete: \(outputURL.lastPathComponent)")
        return outputURL
    }

    private func stagingURL(for outputURL: URL) -> URL {
        outputURL.deletingLastPathComponent()
            .appendingPathComponent(".pending-\(UUID().uuidString)")
            .appendingPathExtension(outputURL.pathExtension)
    }

    private func commit(_ stagingURL: URL, to outputURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputURL.path) {
            _ = try fileManager.replaceItemAt(outputURL, withItemAt: stagingURL)
        } else {
            try fileManager.moveItem(at: stagingURL, to: outputURL)
        }
    }

    private func commitExportDirectory(_ stagingDirectory: URL, primary: URL, to outputURL: URL) throws {
        let fileManager = FileManager.default
        let stagedFiles = try fileManager.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for file in stagedFiles where file != primary {
            try commit(file, to: outputURL.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent))
        }
        try commit(primary, to: outputURL)
    }

    #if DEBUG
    /// DEBUG-only deterministic geometry fixture used by exporter and package tests.
    /// Release products never expose or substitute this asset for a captured model.
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
    #endif
}
