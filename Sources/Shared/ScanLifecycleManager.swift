import Foundation

public enum ScanLifecycleError: LocalizedError, Equatable {
    case invalidName
    case deletionAlreadyCommitted

    public var errorDescription: String? {
        switch self {
        case .invalidName:
            return "A scan name must contain at least one visible character."
        case .deletionAlreadyCommitted:
            return "This scan deletion has already been committed."
        }
    }
}

/// Coordinates user-facing scan metadata changes with app-owned files. SwiftData context saves
/// remain an application-layer responsibility so this service stays deterministic in unit tests.
public struct ScanLifecycleManager: Sendable {
    public let assetStore: ScanAssetStore
    public let exportRoot: URL

    public init(assetStore: ScanAssetStore? = nil, exportRoot: URL? = nil) throws {
        self.assetStore = try assetStore ?? ScanAssetStore()
        self.exportRoot = exportRoot ?? ScanExportLocation.rootDirectory()
    }

    @discardableResult
    public func rename(_ scan: ScanSession, to proposedName: String) throws -> String {
        let name = String(proposedName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !name.isEmpty else { throw ScanLifecycleError.invalidName }
        let previousName = scan.name
        scan.name = name
        do {
            try assetStore.writeManifest(try assetStore.manifest(for: scan))
            return previousName
        } catch {
            scan.name = previousName
            throw error
        }
    }

    /// Moves every app-owned directory out of its live location before SwiftData deletion. The
    /// caller rolls back if its context save fails, or commits after the database deletion saves.
    public func stageDeletion(scanID: UUID) throws -> ScanDeletionTransaction {
        let fileManager = FileManager.default
        let suffix = UUID().uuidString
        var moves: [ScanDeletionTransaction.Move] = []

        let scanDirectory = assetStore.rootDirectory.appendingPathComponent(scanID.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: scanDirectory.path) {
            let staged = assetStore.rootDirectory.appendingPathComponent(".deleting-scan-\(scanID)-\(suffix)", isDirectory: true)
            try fileManager.moveItem(at: scanDirectory, to: staged)
            moves.append(.init(original: scanDirectory, staged: staged))
        }

        let exportDirectory = exportRoot.appendingPathComponent(scanID.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: exportDirectory.path) {
            let stagingRoot = assetStore.rootDirectory.appendingPathComponent(".deleting-exports", isDirectory: true)
            try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            let staged = stagingRoot.appendingPathComponent("\(scanID)-\(suffix)", isDirectory: true)
            do {
                try fileManager.moveItem(at: exportDirectory, to: staged)
                moves.append(.init(original: exportDirectory, staged: staged))
            } catch {
                for move in moves.reversed() {
                    try? fileManager.moveItem(at: move.staged, to: move.original)
                }
                throw error
            }
        }

        return ScanDeletionTransaction(moves: moves)
    }

    /// Removes only raw archives from the oldest completed scans after an explicit user action.
    /// Files are staged until both portable manifests and the caller's model-context save succeed.
    @discardableResult
    public func applyRawArchiveRetention(
        to scans: [ScanSession],
        keepLatest limit: Int,
        save: () throws -> Void
    ) throws -> Int {
        let fileManager = FileManager.default
        let eligible = scans
            .filter { scan in
                guard scan.computeStatus == .completed,
                      scan.hasRenderableAsset,
                      let rawURL = scan.rawArchiveURL,
                      fileManager.fileExists(atPath: rawURL.path) else { return false }
                let scanDirectory = assetStore.rootDirectory
                    .appendingPathComponent(scan.id.uuidString, isDirectory: true)
                    .standardizedFileURL
                let raw = rawURL.standardizedFileURL
                guard raw.path.hasPrefix(scanDirectory.path + "/") else { return false }
                return raw != scan.sourceModelURL?.standardizedFileURL
                    && raw != scan.usdzFileURL?.standardizedFileURL
                    && raw != scan.previewPLYURL?.standardizedFileURL
            }
            .sorted { $0.creationDate > $1.creationDate }
        let targets = Array(eligible.dropFirst(max(0, limit)))
        guard !targets.isEmpty else { return 0 }
        let stagingRoot = assetStore.rootDirectory.appendingPathComponent(".retention-staging", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        var moves: [(scan: ScanSession, original: URL, staged: URL)] = []

        do {
            for scan in targets {
                guard let original = scan.rawArchiveURL else { continue }
                let staged = stagingRoot
                    .appendingPathComponent("\(scan.id)-\(UUID().uuidString)")
                    .appendingPathExtension(original.pathExtension)
                try fileManager.moveItem(at: original, to: staged)
                moves.append((scan, original, staged))
                scan.rawArchiveURL = nil
                try assetStore.writeManifest(try assetStore.manifest(for: scan))
            }
            try save()
            for move in moves { try? fileManager.removeItem(at: move.staged) }
            return moves.count
        } catch {
            for move in moves.reversed() {
                move.scan.rawArchiveURL = move.original
                if fileManager.fileExists(atPath: move.staged.path) {
                    try? fileManager.moveItem(at: move.staged, to: move.original)
                }
                try? assetStore.writeManifest(try assetStore.manifest(for: move.scan))
            }
            throw error
        }
    }
}

public struct ScanStorageAudit: Equatable, Sendable {
    public let orphanURLs: [URL]
    public let totalBytes: Int64

    public init(orphanURLs: [URL], totalBytes: Int64) {
        self.orphanURLs = orphanURLs
        self.totalBytes = totalBytes
    }

    public var itemCount: Int { orphanURLs.count }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

public extension ScanLifecycleManager {
    func auditStorage(liveScanIDs: Set<UUID>) throws -> ScanStorageAudit {
        let fileManager = FileManager.default
        var orphans: [URL] = []
        let liveNames = Set(liveScanIDs.map(\.uuidString))

        if let entries = try? fileManager.contentsOfDirectory(
            at: assetStore.rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries {
                guard entry.lastPathComponent != ".deleting-exports" else { continue }
                if UUID(uuidString: entry.lastPathComponent) != nil, !liveNames.contains(entry.lastPathComponent) {
                    orphans.append(entry)
                }
            }
        }

        let deletingExports = assetStore.rootDirectory.appendingPathComponent(".deleting-exports", isDirectory: true)
        if let stagedExports = try? fileManager.contentsOfDirectory(
            at: deletingExports,
            includingPropertiesForKeys: nil
        ) {
            orphans.append(contentsOf: stagedExports)
        }
        if let stagedScans = try? fileManager.contentsOfDirectory(
            at: assetStore.rootDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            orphans.append(contentsOf: stagedScans.filter { $0.lastPathComponent.hasPrefix(".deleting-scan-") })
        }

        if let exportEntries = try? fileManager.contentsOfDirectory(
            at: exportRoot,
            includingPropertiesForKeys: nil
        ) {
            for entry in exportEntries {
                if UUID(uuidString: entry.lastPathComponent) != nil, !liveNames.contains(entry.lastPathComponent) {
                    orphans.append(entry)
                }
            }
        }

        let unique = Array(Set(orphans.map(\.standardizedFileURL))).sorted { $0.path < $1.path }
        return ScanStorageAudit(
            orphanURLs: unique,
            totalBytes: unique.reduce(0) { $0 + Self.allocatedSize(of: $1) }
        )
    }

    func clean(_ audit: ScanStorageAudit, liveScanIDs: Set<UUID>) throws {
        let liveNames = Set(liveScanIDs.map(\.uuidString))
        for url in audit.orphanURLs {
            let standardized = url.standardizedFileURL
            guard Self.isDescendant(standardized, of: assetStore.rootDirectory)
                    || Self.isDescendant(standardized, of: exportRoot) else { continue }
            guard !liveNames.contains(standardized.lastPathComponent) else { continue }
            if FileManager.default.fileExists(atPath: standardized.path) {
                try FileManager.default.removeItem(at: standardized)
            }
        }
    }

    private static func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var bytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            let fileValues = try? fileURL.resourceValues(forKeys: keys)
            guard fileValues?.isDirectory != true else { continue }
            bytes += Int64(fileValues?.totalFileAllocatedSize ?? fileValues?.fileAllocatedSize ?? 0)
        }
        return bytes
    }

    private static func isDescendant(_ url: URL, of root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path + "/"
        return url.path.hasPrefix(rootPath)
    }
}

public final class ScanDeletionTransaction {
    public struct Move: Equatable {
        public let original: URL
        public let staged: URL

        public init(original: URL, staged: URL) {
            self.original = original
            self.staged = staged
        }
    }

    public let moves: [Move]
    private var isCommitted = false

    init(moves: [Move]) {
        self.moves = moves
    }

    public func commit() throws {
        guard !isCommitted else { throw ScanLifecycleError.deletionAlreadyCommitted }
        for move in moves where FileManager.default.fileExists(atPath: move.staged.path) {
            try FileManager.default.removeItem(at: move.staged)
        }
        isCommitted = true
    }

    public func rollback() throws {
        guard !isCommitted else { throw ScanLifecycleError.deletionAlreadyCommitted }
        for move in moves.reversed() where FileManager.default.fileExists(atPath: move.staged.path) {
            if FileManager.default.fileExists(atPath: move.original.path) {
                try FileManager.default.removeItem(at: move.original)
            }
            try FileManager.default.createDirectory(
                at: move.original.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: move.staged, to: move.original)
        }
    }
}
