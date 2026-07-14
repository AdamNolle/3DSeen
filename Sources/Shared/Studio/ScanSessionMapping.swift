import Foundation

/// Aggregate facts displayed by the scan library. Keeping this derived from persisted sessions
/// prevents the UI from claiming storage, categories, or pending work that does not exist.
public struct ScanLibrarySummary: Equatable {
    public let scanCount: Int
    public let objectCount: Int
    public let spaceCount: Int
    public let landscapeCount: Int
    public let totalSizeMB: Int
    public let pendingComputeCount: Int

    public init(sessions: [ScanSession]) {
        scanCount = sessions.count
        objectCount = sessions.filter { $0.captureMode == .object }.count
        spaceCount = sessions.filter { $0.captureMode == .space }.count
        landscapeCount = sessions.filter { $0.captureMode == .landscape }.count
        totalSizeMB = sessions.reduce(0) { $0 + max(0, $1.sizeMB) }
        pendingComputeCount = sessions.filter { $0.computeStatus != .completed }.count
    }

    public var storageText: String {
        if totalSizeMB < 1_000 { return "\(totalSizeMB) MB" }
        return String(format: "%.1f GB", Double(totalSizeMB) / 1_000)
    }
}

/// Maps a persisted ScanSession into the display model used by ScanThumb / Library.
extension ScanItem {
    init(_ session: ScanSession) {
        let hasModel = session.displayModelURL != nil
        self.init(
            id: session.id.uuidString,
            name: session.name,
            mode: session.captureMode?.rawValue ?? "Object",
            date: session.relativeDate,
            mb: session.sizeMB,
            tier: session.tierRaw,
            tone: session.toneRaw,
            tris: session.triangles,
            primaryAction: Self.libraryAction(for: session, hasModel: hasModel),
            canExport: session.computeStatus == .completed && hasModel
        )
    }

    private static func libraryAction(for session: ScanSession, hasModel: Bool) -> ScanLibraryAction {
        if session.computeStatus == .completed, hasModel { return .view }

        switch session.captureStatus {
        case .draft, .capturing, .needsRetake, .failed:
            return .resumeCapture
        case .captured, .packaged:
            break
        }

        switch session.computeStatus {
        case .failed, .completed:
            return .retryCompute
        case .queued, .local, .offloaded:
            return .resumeCompute
        case .notStarted:
            return .resumeReview
        }
    }
}
