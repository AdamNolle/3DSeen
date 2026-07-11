import Foundation
import ImageIO
import SwiftData

@Model
public final class ScanSession {
    public var id: UUID
    public var creationDate: Date
    public var captureModeRaw: String
    public var usdzFileURL: URL?
    public var appliedMaterialRaw: String?
    public var rawArchiveURL: URL?
    public var sourceModelURL: URL?
    public var thumbnailURL: URL?
    public var previewPLYURL: URL?
    /// Distinguishes an actual trained radiance field from a geometry-derived viewer preview.
    public var previewPLYKindRaw: String = SplatPreviewKind.geometryPreview.rawValue
    public var lastExportedURL: URL?
    public var captureStatusRaw: String
    public var computeStatusRaw: String

    // Display metadata (defaulted so SwiftData lightweight migration is automatic).
    public var name: String = "New Scan"
    public var sizeMB: Int = 0
    public var tierRaw: String = "Medium"
    public var toneRaw: String = "bone"
    public var triangles: String = "—"
    public var frameCount: Int = 0
    public var coveragePercent: Int = 0
    public var weakSpotCount: Int = 0
    /// JSON-backed because SwiftData does not persist an array of custom value types directly.
    public var measurementsJSON: String = "[]"
    /// JSON-backed because a report is a value type and must survive relaunches and handoffs.
    public var captureQualityReportJSON: String = ""

    // Computed properties for safe typed access
    public var captureMode: CaptureMode? {
        CaptureMode(rawValue: captureModeRaw)
    }

    public var captureStatus: ScanCaptureStatus {
        ScanCaptureStatus(rawValue: captureStatusRaw) ?? .draft
    }

    public var computeStatus: ScanComputeStatus {
        ScanComputeStatus(rawValue: computeStatusRaw) ?? .notStarted
    }

    public var displayModelURL: URL? {
        [usdzFileURL, sourceModelURL, previewPLYURL]
            .compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public var hasRenderableAsset: Bool {
        displayModelURL != nil
    }

    public var previewPLYKind: SplatPreviewKind {
        get { SplatPreviewKind(rawValue: previewPLYKindRaw) ?? .geometryPreview }
        set { previewPLYKindRaw = newValue.rawValue }
    }

    public var measurements: [ScanMeasurement] {
        get {
            guard let data = measurementsJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([ScanMeasurement].self, from: data)) ?? []
        }
        set {
            measurementsJSON = String(
                data: (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8),
                encoding: .utf8
            ) ?? "[]"
        }
    }

    public var captureQualityReport: CaptureQualityReport? {
        get {
            guard !captureQualityReportJSON.isEmpty,
                  let data = captureQualityReportJSON.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(CaptureQualityReport.self, from: data)
        }
        set {
            guard let newValue,
                  let data = try? JSONEncoder().encode(newValue),
                  let value = String(data: data, encoding: .utf8) else {
                captureQualityReportJSON = ""
                return
            }
            captureQualityReportJSON = value
        }
    }

    public var exportFileBaseName: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let collapsed = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        let sanitized = String(collapsed)
            .split(separator: "-")
            .joined(separator: "-")
        return sanitized.isEmpty ? "scan-\(id.uuidString.lowercased())" : sanitized
    }

    public init(id: UUID = UUID(),
                creationDate: Date = Date(),
                captureMode: CaptureMode,
                name: String = "New Scan",
                sizeMB: Int = 0,
                tier: String = "Medium",
                tone: String = "bone",
                triangles: String = "—",
                usdzFileURL: URL? = nil,
                rawArchiveURL: URL? = nil,
                sourceModelURL: URL? = nil,
                thumbnailURL: URL? = nil,
                previewPLYURL: URL? = nil,
                previewPLYKind: SplatPreviewKind = .geometryPreview,
                captureStatus: ScanCaptureStatus = .draft,
                computeStatus: ScanComputeStatus = .notStarted,
                frameCount: Int = 0,
                coveragePercent: Int = 0,
                weakSpotCount: Int = 0,
                captureQualityReport: CaptureQualityReport? = nil) {
        self.id = id
        self.creationDate = creationDate
        self.captureModeRaw = captureMode.rawValue
        self.usdzFileURL = usdzFileURL
        self.rawArchiveURL = rawArchiveURL
        self.sourceModelURL = sourceModelURL
        self.thumbnailURL = thumbnailURL
        self.previewPLYURL = previewPLYURL
        self.previewPLYKindRaw = previewPLYKind.rawValue
        self.lastExportedURL = nil
        self.captureStatusRaw = captureStatus.rawValue
        self.computeStatusRaw = computeStatus.rawValue
        self.name = name
        self.sizeMB = sizeMB
        self.tierRaw = tier
        self.toneRaw = tone
        self.triangles = triangles
        self.frameCount = frameCount
        self.coveragePercent = coveragePercent
        self.weakSpotCount = weakSpotCount
        self.captureQualityReport = captureQualityReport
    }

    /// Human relative date ("Today", "5d ago", "Aug 04").
    public var relativeDate: String {
        let cal = Calendar.current
        if cal.isDateInToday(creationDate) { return "Today" }
        let days = cal.dateComponents([.day], from: creationDate, to: Date()).day ?? 0
        switch days {
        case ..<1:    return "Today"
        case 1:       return "Yesterday"
        case 2...13:  return "\(days)d ago"
        case 14...27: return "\(days / 7)w ago"
        default:
            let formatter = DateFormatter(); formatter.dateFormat = "MMM dd"
            return formatter.string(from: creationDate)
        }
    }
}

/// A user-measured distance between two model-space points. Computed USDZ coordinates are in
/// metres, so `meters` is directly suitable for metric or imperial display.
public struct ScanMeasurementPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x; self.y = y; self.z = z
    }
}

public struct ScanMeasurement: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var start: ScanMeasurementPoint
    public var end: ScanMeasurementPoint
    public var label: String

    public init(id: UUID = UUID(), start: ScanMeasurementPoint, end: ScanMeasurementPoint, label: String = "Distance") {
        self.id = id
        self.start = start
        self.end = end
        self.label = label
    }

    public var meters: Double {
        let dx = end.x - start.x, dy = end.y - start.y, dz = end.z - start.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }
}

/// Reads the actual image files in a capture archive. Capture and reconstruction use the same
/// recursive definition, so a scan cannot be saved as valid with an empty frame package.
public enum CaptureArchiveInspector {
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "heic", "png"]

    public static func containsImageFrames(in archive: URL) -> Bool {
        imageURLs(in: archive).contains(where: isDecodableImage)
    }

    public static func imageFrameCount(in archive: URL) -> Int {
        imageURLs(in: archive).count
    }

    public static func decodableImageFrameCount(in archive: URL) -> Int {
        imageURLs(in: archive).filter(isDecodableImage).count
    }

    private static func imageURLs(in archive: URL) -> [URL] {
        guard let files = FileManager.default.enumerator(at: archive, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.compactMap { $0 as? URL }
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
    }

    private static func isDecodableImage(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return false }
        return width.intValue > 0 && height.intValue > 0
    }
}

public enum ScanCaptureStatus: String, Codable, CaseIterable, Sendable {
    case draft = "Draft"
    case capturing = "Capturing"
    case captured = "Captured"
    case needsRetake = "Needs Retake"
    case packaged = "Packaged"
    case failed = "Failed"
}

public enum ScanComputeStatus: String, Codable, CaseIterable, Sendable {
    case notStarted = "Not Started"
    case queued = "Queued"
    case local = "Computing Locally"
    case offloaded = "Offloaded"
    case completed = "Completed"
    case failed = "Failed"
}

public enum SplatPreviewKind: String, Codable, CaseIterable, Sendable {
    case geometryPreview = "Geometry Preview"
    case trainedSplat = "Trained Splat"
}

public struct ScanAssetManifest: Codable, Equatable, Sendable {
    public var scanID: UUID
    public var captureModeRaw: String
    public var detailTier: String
    public var rawArchiveURL: URL?
    public var sourceModelURL: URL?
    public var usdzFileURL: URL?
    public var previewPLYURL: URL?
    /// Optional raw backing preserves compatibility with result manifests created before trained
    /// splats were supported.
    public var previewPLYKindRaw: String?

    public var previewPLYKind: SplatPreviewKind {
        SplatPreviewKind(rawValue: previewPLYKindRaw ?? "") ?? .geometryPreview
    }
    public var thumbnailURL: URL?
    public var frameCount: Int
    public var coveragePercent: Int
    public var weakSpotCount: Int
    public var captureQualityReport: CaptureQualityReport?

    public var captureMode: CaptureMode {
        CaptureMode(rawValue: captureModeRaw) ?? .object
    }

    public init(scanID: UUID,
                captureMode: CaptureMode,
                detailTier: String,
                rawArchiveURL: URL? = nil,
                sourceModelURL: URL? = nil,
                usdzFileURL: URL? = nil,
                previewPLYURL: URL? = nil,
                previewPLYKind: SplatPreviewKind = .geometryPreview,
                thumbnailURL: URL? = nil,
                frameCount: Int = 0,
                coveragePercent: Int = 0,
                weakSpotCount: Int = 0,
                captureQualityReport: CaptureQualityReport? = nil) {
        self.scanID = scanID
        self.captureModeRaw = captureMode.rawValue
        self.detailTier = detailTier
        self.rawArchiveURL = rawArchiveURL
        self.sourceModelURL = sourceModelURL
        self.usdzFileURL = usdzFileURL
        self.previewPLYURL = previewPLYURL
        self.previewPLYKindRaw = previewPLYKind.rawValue
        self.thumbnailURL = thumbnailURL
        self.frameCount = frameCount
        self.coveragePercent = coveragePercent
        self.weakSpotCount = weakSpotCount
        self.captureQualityReport = captureQualityReport
    }
}

public extension ScanSession {
    func apply(manifest: ScanAssetManifest) {
        captureModeRaw = manifest.captureMode.rawValue
        tierRaw = manifest.detailTier
        rawArchiveURL = manifest.rawArchiveURL
        sourceModelURL = manifest.sourceModelURL
        usdzFileURL = manifest.usdzFileURL
        previewPLYURL = manifest.previewPLYURL
        previewPLYKind = manifest.previewPLYKind
        thumbnailURL = manifest.thumbnailURL
        frameCount = manifest.frameCount
        coveragePercent = manifest.coveragePercent
        weakSpotCount = manifest.weakSpotCount
        captureQualityReport = manifest.captureQualityReport
        captureStatusRaw = manifest.weakSpotCount > 0 ? ScanCaptureStatus.needsRetake.rawValue : ScanCaptureStatus.captured.rawValue
    }

    func markPackaged(rawArchiveURL: URL?) {
        self.rawArchiveURL = rawArchiveURL
        captureStatusRaw = ScanCaptureStatus.packaged.rawValue
        computeStatusRaw = ScanComputeStatus.queued.rawValue
    }

    func markComputed(modelURL: URL, usdzURL: URL? = nil, previewPLYURL: URL? = nil,
                      previewPLYKind: SplatPreviewKind = .geometryPreview) {
        sourceModelURL = modelURL
        usdzFileURL = usdzURL ?? usdzFileURL
        self.previewPLYURL = previewPLYURL ?? self.previewPLYURL
        if previewPLYURL != nil { self.previewPLYKind = previewPLYKind }
        computeStatusRaw = ScanComputeStatus.completed.rawValue
    }
}

public struct ScanAssetStore: Sendable {
    public enum StoreError: LocalizedError {
        case applicationSupportUnavailable
        case missingCaptureMode
        case manifestIdentityMismatch(expected: UUID, actual: UUID)

        public var errorDescription: String? {
            switch self {
            case .applicationSupportUnavailable:
                "Unable to locate the application support directory."
            case .missingCaptureMode:
                "The scan does not have a valid capture mode."
            case .manifestIdentityMismatch(let expected, let actual):
                "Manifest \(actual.uuidString) cannot be registered on scan \(expected.uuidString)."
            }
        }
    }

    public let rootDirectory: URL

    public init(rootDirectory: URL? = nil) throws {
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            guard let baseURL = urls.first else {
                throw StoreError.applicationSupportUnavailable
            }
            self.rootDirectory = baseURL
                .appendingPathComponent("3DSeen", isDirectory: true)
                .appendingPathComponent("Scans", isDirectory: true)
        }

        try FileManager.default.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
    }

    public func directory(for scanID: UUID) throws -> URL {
        let url = rootDirectory.appendingPathComponent(scanID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Copies raw capture data out of a temporary camera directory and into the scan's durable
    /// application-support folder. The returned URL is the only path that should be persisted.
    public func importCapture(from source: URL, for scanID: UUID, named preferredName: String? = nil) throws -> URL {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let scanDirectory = try directory(for: scanID)
        let destinationName = preferredName ?? (isDirectory.boolValue ? "capture" : source.lastPathComponent)
        let destination = scanDirectory.appendingPathComponent(destinationName, isDirectory: isDirectory.boolValue)
        let staging = scanDirectory.appendingPathComponent(".incoming-\(UUID().uuidString)", isDirectory: isDirectory.boolValue)
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: source, to: staging)
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: destination)
        }
        return destination
    }

    public func manifestURL(for scanID: UUID) throws -> URL {
        try directory(for: scanID).appendingPathComponent("manifest.json")
    }

    public func writeManifest(_ manifest: ScanAssetManifest) throws {
        try writeManifest(manifest, to: try directory(for: manifest.scanID))
    }

    public func writeManifest(_ manifest: ScanAssetManifest, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.scanManifest.encode(portable(manifest))
        try data.write(to: directory.appendingPathComponent("manifest.json"), options: [.atomic])
    }

    public func loadManifest(for scanID: UUID) throws -> ScanAssetManifest {
        let data = try Data(contentsOf: manifestURL(for: scanID))
        let manifest = try JSONDecoder.scanManifest.decode(ScanAssetManifest.self, from: data)
        guard manifest.scanID == scanID else {
            throw StoreError.manifestIdentityMismatch(expected: scanID, actual: manifest.scanID)
        }
        return try resolved(manifest)
    }

    public func register(_ manifest: ScanAssetManifest, on session: ScanSession) throws {
        guard manifest.scanID == session.id else {
            throw StoreError.manifestIdentityMismatch(expected: session.id, actual: manifest.scanID)
        }
        let resolvedManifest = try resolved(manifest)
        try writeManifest(resolvedManifest)
        session.apply(manifest: resolvedManifest)
    }

    public func manifest(for session: ScanSession) throws -> ScanAssetManifest {
        guard let mode = session.captureMode else {
            throw StoreError.missingCaptureMode
        }

        return ScanAssetManifest(
            scanID: session.id,
            captureMode: mode,
            detailTier: session.tierRaw,
            rawArchiveURL: resolvedPersistedURL(session.rawArchiveURL, for: session.id),
            sourceModelURL: resolvedPersistedURL(session.sourceModelURL, for: session.id),
            usdzFileURL: resolvedPersistedURL(session.usdzFileURL, for: session.id),
            previewPLYURL: resolvedPersistedURL(session.previewPLYURL, for: session.id),
            previewPLYKind: session.previewPLYKind,
            thumbnailURL: resolvedPersistedURL(session.thumbnailURL, for: session.id),
            frameCount: session.frameCount,
            coveragePercent: session.coveragePercent,
            weakSpotCount: session.weakSpotCount,
            captureQualityReport: session.captureQualityReport
        )
    }

    public func repairPersistedURLs(on session: ScanSession) {
        session.rawArchiveURL = resolvedPersistedURL(session.rawArchiveURL, for: session.id)
        session.sourceModelURL = resolvedPersistedURL(session.sourceModelURL, for: session.id)
        session.usdzFileURL = resolvedPersistedURL(session.usdzFileURL, for: session.id)
        session.previewPLYURL = resolvedPersistedURL(session.previewPLYURL, for: session.id)
        session.thumbnailURL = resolvedPersistedURL(session.thumbnailURL, for: session.id)
    }

    public func resolvedPersistedURL(_ url: URL?, for scanID: UUID) -> URL? {
        guard let url else { return nil }
        let scanDirectory = rootDirectory.appendingPathComponent(scanID.uuidString, isDirectory: true)
        if !url.isFileURL {
            return scanDirectory.appendingPathComponent(url.relativeString.removingPercentEncoding ?? url.relativeString)
        }
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let components = url.standardizedFileURL.pathComponents
        guard let scanIndex = components.lastIndex(of: scanID.uuidString), scanIndex + 1 < components.count else {
            return url
        }
        return components[(scanIndex + 1)...].reduce(scanDirectory) { partial, component in
            partial.appendingPathComponent(component)
        }
    }

    private func portable(_ manifest: ScanAssetManifest) throws -> ScanAssetManifest {
        var result = manifest
        let scanDirectory = rootDirectory.appendingPathComponent(manifest.scanID.uuidString, isDirectory: true)
        result.rawArchiveURL = relativeURL(manifest.rawArchiveURL, under: scanDirectory)
        result.sourceModelURL = relativeURL(manifest.sourceModelURL, under: scanDirectory)
        result.usdzFileURL = relativeURL(manifest.usdzFileURL, under: scanDirectory)
        result.previewPLYURL = relativeURL(manifest.previewPLYURL, under: scanDirectory)
        result.thumbnailURL = relativeURL(manifest.thumbnailURL, under: scanDirectory)
        return result
    }

    private func resolved(_ manifest: ScanAssetManifest) throws -> ScanAssetManifest {
        var result = manifest
        result.rawArchiveURL = resolvedPersistedURL(manifest.rawArchiveURL, for: manifest.scanID)
        result.sourceModelURL = resolvedPersistedURL(manifest.sourceModelURL, for: manifest.scanID)
        result.usdzFileURL = resolvedPersistedURL(manifest.usdzFileURL, for: manifest.scanID)
        result.previewPLYURL = resolvedPersistedURL(manifest.previewPLYURL, for: manifest.scanID)
        result.thumbnailURL = resolvedPersistedURL(manifest.thumbnailURL, for: manifest.scanID)
        return result
    }

    private func relativeURL(_ url: URL?, under scanDirectory: URL) -> URL? {
        guard let url else { return nil }
        let rootPath = scanDirectory.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url }
        let relativePath = String(path.dropFirst(rootPath.count))
        return URL(string: relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relativePath)
    }
}

private extension JSONEncoder {
    static var scanManifest: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var scanManifest: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
