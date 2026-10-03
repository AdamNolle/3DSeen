import Foundation
import XCTest
import ZIPFoundation
#if os(macOS)
@testable import ThreeDSeenMac
#else
@testable import ThreeDSeen
#endif

final class BoundedArchiveExtractorTests: XCTestCase {
    func testRejectsPathTraversalWithoutWritingOutsideDestination() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archiveURL = root.appendingPathComponent("traversal.zip")
        let destination = root.appendingPathComponent("extracted", isDirectory: true)
        try makeArchive(at: archiveURL, entries: [("../escape.txt", Data("blocked".utf8))])

        XCTAssertThrowsError(try BoundedArchiveExtractor.extract(archiveURL, to: destination)) { error in
            guard let extractionError = error as? BoundedArchiveExtractor.ExtractionError,
                  case .invalidPath = extractionError
            else {
                return XCTFail("Expected unsafe archive path rejection, received \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix(".3dseen-extract-")
        }.isEmpty)
    }

    func testRejectsSymbolicLinks() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archiveURL = root.appendingPathComponent("symlink.zip")
        let destination = root.appendingPathComponent("extracted", isDirectory: true)
        let linkTarget = Data("../../outside.txt".utf8)
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(
            with: "link.txt",
            type: .symlink,
            uncompressedSize: Int64(linkTarget.count),
            compressionMethod: .none
        ) { position, requestedSize in
            let start = Int(position)
            guard start < linkTarget.count else { return Data() }
            let end = min(start + requestedSize, linkTarget.count)
            return linkTarget.subdata(in: start..<end)
        }

        XCTAssertThrowsError(try BoundedArchiveExtractor.extract(archiveURL, to: destination)) { error in
            guard let extractionError = error as? BoundedArchiveExtractor.ExtractionError,
                  case .unsupportedEntryType = extractionError
            else {
                return XCTFail("Expected symbolic-link rejection, received \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testEnforcesPerEntryExpandedByteLimit() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archiveURL = root.appendingPathComponent("oversized.zip")
        try makeArchive(at: archiveURL, entries: [("one.bin", Data(repeating: 1, count: 5))])
        let destination = root.appendingPathComponent("limited", isDirectory: true)
        let limits = BoundedArchiveExtractor.Limits(
            maximumEntryCount: 2,
            maximumEntryBytes: 4,
            maximumExpandedBytes: 4
        )

        XCTAssertThrowsError(try BoundedArchiveExtractor.extract(archiveURL, to: destination, limits: limits)) { error in
            guard let extractionError = error as? BoundedArchiveExtractor.ExtractionError,
                  case .expandedSizeLimitExceeded = extractionError
            else {
                return XCTFail("Expected expanded-size rejection, received \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testEnforcesAggregateExpandedByteLimitAcrossEntries() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archiveURL = root.appendingPathComponent("expanded-total.zip")
        try makeArchive(at: archiveURL, entries: [
            ("one.bin", Data(repeating: 1, count: 3)),
            ("two.bin", Data(repeating: 2, count: 3))
        ])
        let destination = root.appendingPathComponent("limited", isDirectory: true)
        let limits = BoundedArchiveExtractor.Limits(
            maximumEntryCount: 4,
            maximumEntryBytes: 4,
            maximumExpandedBytes: 4
        )

        XCTAssertThrowsError(try BoundedArchiveExtractor.extract(archiveURL, to: destination, limits: limits)) { error in
            guard let extractionError = error as? BoundedArchiveExtractor.ExtractionError,
                  case .expandedSizeLimitExceeded = extractionError
            else {
                return XCTFail("Expected aggregate expanded-size rejection, received \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testRejectsTooManyEntriesBeforeCommittingExtraction() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archiveURL = root.appendingPathComponent("many-files.zip")
        try makeArchive(at: archiveURL, entries: [
            ("one.txt", Data("one".utf8)),
            ("two.txt", Data("two".utf8))
        ])
        let destination = root.appendingPathComponent("limited", isDirectory: true)
        let limits = BoundedArchiveExtractor.Limits(
            maximumEntryCount: 1,
            maximumEntryBytes: 16,
            maximumExpandedBytes: 16
        )

        XCTAssertThrowsError(try BoundedArchiveExtractor.extract(archiveURL, to: destination, limits: limits)) { error in
            guard let extractionError = error as? BoundedArchiveExtractor.ExtractionError,
                  case .entryLimitExceeded = extractionError
            else {
                return XCTFail("Expected entry-count rejection, received \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testNonemptyDestinationIsPreservedAndValidArchiveExtracts() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archiveURL = root.appendingPathComponent("valid.zip")
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        let existingFile = destination.appendingPathComponent("keep.txt")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: existingFile)
        try makeArchive(at: archiveURL, entries: [("nested/model.txt", Data("mesh".utf8))])

        XCTAssertThrowsError(try BoundedArchiveExtractor.extract(archiveURL, to: destination)) { error in
            guard let extractionError = error as? BoundedArchiveExtractor.ExtractionError,
                  case .destinationNotEmpty = extractionError
            else {
                return XCTFail("Expected nonempty destination rejection, received \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: existingFile), Data("keep".utf8))

        try FileManager.default.removeItem(at: existingFile)
        try BoundedArchiveExtractor.extract(archiveURL, to: destination)
        let extractedFile = destination.appendingPathComponent("nested/model.txt")
        XCTAssertEqual(try Data(contentsOf: extractedFile), Data("mesh".utf8))
    }

    func testMetadataReaderReadsBoundedRegularFilesAndRejectsOversizedFiles() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("metadata.json")
        try Data("{}".utf8).write(to: url)
        XCTAssertEqual(try BoundedArchiveExtractor.readMetadataFile(at: url, maximumByteCount: 16), Data("{}".utf8))

        try Data(repeating: 0x20, count: 17).write(to: url)
        XCTAssertThrowsError(try BoundedArchiveExtractor.readMetadataFile(at: url, maximumByteCount: 16)) { error in
            guard let extractionError = error as? BoundedArchiveExtractor.ExtractionError,
                  case .metadataFileLimitExceeded = extractionError else {
                return XCTFail("Expected metadata size rejection, received \(error)")
            }
        }
    }

    private func makeArchive(at url: URL, entries: [(path: String, data: Data)]) throws {
        let archive = try Archive(url: url, accessMode: .create)
        for entry in entries {
            try archive.addEntry(
                with: entry.path,
                type: .file,
                uncompressedSize: Int64(entry.data.count),
                compressionMethod: .none
            ) { position, requestedSize in
                let start = Int(position)
                guard start < entry.data.count else { return Data() }
                let end = min(start + requestedSize, entry.data.count)
                return entry.data.subdata(in: start..<end)
            }
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoundedArchiveExtractorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
