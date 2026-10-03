import Foundation

struct LiDARCaptureReport: Codable, Sendable {
    let schemaVersion: Int
    let triangleCount: Int
    let texturedTriangleCount: Int
    let textureFrameCount: Int
    let textureSnapshotCount: Int
    let surfaceCounts: [String: Int]?
    let modelFileName: String?
    let trackedObjectCount: Int?

    init(schemaVersion: Int, triangleCount: Int, texturedTriangleCount: Int,
         textureFrameCount: Int, textureSnapshotCount: Int, surfaceCounts: [String: Int]? = nil,
         modelFileName: String? = nil, trackedObjectCount: Int? = nil) {
        self.schemaVersion = schemaVersion
        self.triangleCount = triangleCount
        self.texturedTriangleCount = texturedTriangleCount
        self.textureFrameCount = textureFrameCount
        self.textureSnapshotCount = textureSnapshotCount
        self.surfaceCounts = surfaceCounts
        self.modelFileName = modelFileName
        self.trackedObjectCount = trackedObjectCount
    }
}

/// Keep reusable textures and the finished model outside the removable source-photo archive.
enum LiDARCaptureBundle {
    static let modelName = "space.usdz"
    static let objectModelName = "object.usdz"
    static let reportName = "surface-capture.json"
    static let framesName = "capture"
    static let texturesName = "textures"

    struct Imported: Sendable {
        let modelURL: URL
        let archiveURL: URL
        let report: LiDARCaptureReport
    }

    static func importCapture(from source: URL, scanID: UUID, store: ScanAssetStore) throws -> Imported {
        let report = try JSONDecoder().decode(LiDARCaptureReport.self, from: Data(contentsOf: source.appendingPathComponent(reportName)))
        let modelName = report.modelFileName ?? Self.modelName
        guard [Self.modelName, Self.objectModelName].contains(modelName) else {
            throw LiDARSurfaceError.invalidGeometry
        }
        let model = source.appendingPathComponent(modelName)
        let frames = source.appendingPathComponent(framesName)
        guard (1...3).contains(report.schemaVersion), report.triangleCount > 0,
              report.texturedTriangleCount > 0, report.texturedTriangleCount <= report.triangleCount,
              report.textureFrameCount > 0, report.textureSnapshotCount >= 0,
              report.trackedObjectCount.map({ $0 >= 0 }) ?? (report.schemaVersion < 3),
              report.surfaceCounts.map({ counts in
                  counts.values.allSatisfy { $0 >= 0 } && counts.values.reduce(0, +) == report.triangleCount
              }) ?? (report.schemaVersion == 1),
              ModelGeometryInspector.inspect(modelURL: model)?.triangleCount == report.triangleCount,
              CaptureArchiveInspector.containsImageFrames(in: frames) else {
            throw LiDARSurfaceError.invalidGeometry
        }
        let modelURL = try store.importCapture(from: model, for: scanID, named: modelName)
        let archiveURL = try store.importCapture(from: frames, for: scanID, named: framesName)
        _ = try store.importCapture(from: source.appendingPathComponent(reportName), for: scanID, named: reportName)
        if report.textureSnapshotCount > 0 {
            _ = try store.importCapture(from: source.appendingPathComponent(texturesName), for: scanID, named: texturesName)
        }
        return Imported(modelURL: modelURL, archiveURL: archiveURL, report: report)
    }

    static func textureSnapshots(for modelURL: URL?) -> [URL] {
        guard let modelURL else { return [] }
        let directory = modelURL.deletingLastPathComponent().appendingPathComponent(texturesName)
        return ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "png" && $0.lastPathComponent.hasPrefix("texture_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
