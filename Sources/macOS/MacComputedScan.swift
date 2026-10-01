import Foundation

/// A completed model retained by the Mac app. The record is reconstructed from the durable
/// scan manifest at launch, rather than from design-time sample data.
public struct MacComputedScan: Identifiable, Equatable {
    public let manifest: ScanAssetManifest
    public let modelURL: URL
    public let byteCount: Int64
    public let creationDate: Date

    public var id: UUID { manifest.scanID }
    public var name: String {
        manifest.displayName ?? "\(manifest.captureMode.rawValue)-\(manifest.scanID.uuidString.prefix(8))"
    }
    public var sizeMB: Int { max(0, Int((Double(byteCount) / 1_000_000).rounded(.up))) }
    public var isRenderable: Bool { FileManager.default.fileExists(atPath: modelURL.path) }
}

/// Derived display facts for the desktop library. Counts and storage always originate from
/// actual persisted scan records, so an empty library stays empty.
public struct MacLibrarySummary: Equatable {
    public let scanCount: Int
    public let objectCount: Int
    public let spaceCount: Int
    public let landscapeCount: Int
    public let totalByteCount: Int64

    public init(scans: [MacComputedScan]) {
        scanCount = scans.count
        objectCount = scans.filter { $0.manifest.captureMode == .object }.count
        spaceCount = scans.filter { $0.manifest.captureMode == .space }.count
        landscapeCount = scans.filter { $0.manifest.captureMode == .landscape }.count
        totalByteCount = scans.reduce(0) { $0 + max(0, $1.byteCount) }
    }

    public var storageText: String {
        if totalByteCount < 1_000_000 { return "\(totalByteCount / 1_000) KB" }
        if totalByteCount < 1_000_000_000 { return String(format: "%.1f MB", Double(totalByteCount) / 1_000_000) }
        return String(format: "%.2f GB", Double(totalByteCount) / 1_000_000_000)
    }
}

extension ComputeCoordinator {
    public enum SplatOutput: String, CaseIterable, Identifiable {
        case geometryPreview
        case trainedSplat

        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .geometryPreview: return "Geometry preview"
            case .trainedSplat: return "Trained splat"
            }
        }
    }
}
