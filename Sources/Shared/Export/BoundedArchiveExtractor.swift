import Foundation
import ZIPFoundation

enum BoundedArchiveExtractor {
    struct Limits {
        let maximumEntryCount: Int
        let maximumEntryBytes: UInt64
        let maximumExpandedBytes: UInt64

        static let standard = Limits(
            maximumEntryCount: 10_000,
            maximumEntryBytes: 4 * 1_024 * 1_024 * 1_024,
            maximumExpandedBytes: 8 * 1_024 * 1_024 * 1_024
        )
    }

    enum ExtractionError: LocalizedError {
        case archiveSizeLimitExceeded
        case metadataFileLimitExceeded(String)
        case invalidPath(String)
        case unsupportedEntryType(String)
        case entryLimitExceeded
        case expandedSizeLimitExceeded
        case destinationNotEmpty
        case malformedEntry(String)

        var errorDescription: String? {
            switch self {
            case .archiveSizeLimitExceeded:
                return "The archive file exceeds the allowed size."
            case .metadataFileLimitExceeded(let name):
                return "The archive metadata file exceeds the allowed size: \(name)."
            case .invalidPath(let path):
                return "The archive contains an unsafe path: \(path)"
            case .unsupportedEntryType(let path):
                return "The archive contains an unsupported link: \(path)"
            case .entryLimitExceeded:
                return "The archive contains too many files."
            case .expandedSizeLimitExceeded:
                return "The archive expands beyond the allowed size."
            case .destinationNotEmpty:
                return "The extraction destination is not empty."
            case .malformedEntry(let path):
                return "The archive entry is malformed: \(path)"
            }
        }
    }

    static func readMetadataFile(at url: URL, maximumByteCount: Int) throws -> Data {
        guard maximumByteCount > 0,
              maximumByteCount < Int.max,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize >= 0,
              fileSize <= maximumByteCount else {
            throw ExtractionError.metadataFileLimitExceeded(url.lastPathComponent)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let readLimit = maximumByteCount + 1
        var data = Data()
        data.reserveCapacity(fileSize)
        while data.count < readLimit {
            guard let chunk = try handle.read(upToCount: min(64 * 1_024, readLimit - data.count)),
                  !chunk.isEmpty else { break }
            data.append(contentsOf: chunk)
        }
        guard data.count <= maximumByteCount, data.count == fileSize else {
            throw ExtractionError.metadataFileLimitExceeded(url.lastPathComponent)
        }
        return data
    }

    static func extract(
        _ archiveURL: URL,
        to destination: URL,
        limits: Limits = .standard
    ) throws {
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let staging = parent.appendingPathComponent(
            ".3dseen-extract-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        var stagingWasMoved = false
        defer {
            if !stagingWasMoved {
                try? fileManager.removeItem(at: staging)
            }
        }

        let archiveFileSize = try archiveURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard archiveFileSize > 0,
              !HandoffResourceAdmissionPolicy.exceedsSizeLimit(Int64(archiveFileSize)) else {
            throw ExtractionError.archiveSizeLimitExceeded
        }
        let archive = try Archive(url: archiveURL, accessMode: .read)
        var entryCount = 0
        var advertisedExpandedBytes: UInt64 = 0
        var actualExpandedBytes: UInt64 = 0

        for entry in archive {
            entryCount += 1
            guard entryCount <= limits.maximumEntryCount else {
                throw ExtractionError.entryLimitExceeded
            }
            guard entry.uncompressedSize <= limits.maximumEntryBytes else {
                throw ExtractionError.expandedSizeLimitExceeded
            }
            let (advertisedTotal, advertisedOverflow) = advertisedExpandedBytes
                .addingReportingOverflow(entry.uncompressedSize)
            guard !advertisedOverflow, advertisedTotal <= limits.maximumExpandedBytes else {
                throw ExtractionError.expandedSizeLimitExceeded
            }
            advertisedExpandedBytes = advertisedTotal

            let output = try outputURL(for: entry.path, in: staging)
            switch entry.type {
            case .directory:
                guard entry.uncompressedSize == 0 else {
                    throw ExtractionError.malformedEntry(entry.path)
                }
                try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
            case .file:
                guard !fileManager.fileExists(atPath: output.path) else {
                    throw ExtractionError.invalidPath(entry.path)
                }
                try fileManager.createDirectory(
                    at: output.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                guard fileManager.createFile(atPath: output.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let handle = try FileHandle(forWritingTo: output)
                var entryExpandedBytes: UInt64 = 0
                do {
                    _ = try archive.extract(entry, consumer: { chunk in
                        let (entryTotal, entryOverflow) = entryExpandedBytes
                            .addingReportingOverflow(UInt64(chunk.count))
                        let (archiveTotal, archiveOverflow) = actualExpandedBytes
                            .addingReportingOverflow(UInt64(chunk.count))
                        guard !entryOverflow, !archiveOverflow,
                              entryTotal <= limits.maximumEntryBytes,
                              archiveTotal <= limits.maximumExpandedBytes else {
                            throw ExtractionError.expandedSizeLimitExceeded
                        }
                        entryExpandedBytes = entryTotal
                        actualExpandedBytes = archiveTotal
                        try handle.write(contentsOf: chunk)
                    })
                    try handle.close()
                } catch {
                    try? handle.close()
                    throw error
                }
                guard entryExpandedBytes == entry.uncompressedSize else {
                    throw ExtractionError.malformedEntry(entry.path)
                }
            case .symlink:
                throw ExtractionError.unsupportedEntryType(entry.path)
            }
        }

        if fileManager.fileExists(atPath: destination.path) {
            let existingItems = try fileManager.contentsOfDirectory(
                at: destination,
                includingPropertiesForKeys: nil
            )
            guard existingItems.isEmpty else { throw ExtractionError.destinationNotEmpty }
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: staging, to: destination)
        stagingWasMoved = true
    }

    private static func outputURL(for path: String, in staging: URL) throws -> URL {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains(":"),
              !path.unicodeScalars.contains(where: { $0.value == 0 }),
              path.utf8.count <= 1_024 else {
            throw ExtractionError.invalidPath(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw ExtractionError.invalidPath(path)
        }

        let output = staging.appendingPathComponent(path).standardizedFileURL
        let root = staging.standardizedFileURL.path + "/"
        guard output.path.hasPrefix(root) else { throw ExtractionError.invalidPath(path) }
        return output
    }
}
