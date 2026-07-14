import XCTest
@testable import ThreeDSeen

final class ScanLifecycleManagerTests: XCTestCase {
    func testRenameUpdatesPortableManifestAndRejectsEmptyName() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let session = ScanSession(captureMode: .object, name: "Original")
        _ = try fixture.store.directory(for: session.id)
        try fixture.store.writeManifest(try fixture.store.manifest(for: session))

        let previous = try fixture.manager.rename(session, to: "  Gallery Bust  ")
        let manifest = try fixture.store.loadManifest(for: session.id)

        XCTAssertEqual(previous, "Original")
        XCTAssertEqual(session.name, "Gallery Bust")
        XCTAssertEqual(manifest.displayName, "Gallery Bust")
        XCTAssertThrowsError(try fixture.manager.rename(session, to: "   "))
        XCTAssertEqual(session.name, "Gallery Bust")
    }

    func testDeletionRollbackRestoresAssetsAndAppOwnedExports() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let scanID = UUID()
        let asset = try fixture.store.directory(for: scanID).appendingPathComponent("model.usdz")
        try Data("model".utf8).write(to: asset)
        let exportDirectory = fixture.exportRoot.appendingPathComponent(scanID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let exported = exportDirectory.appendingPathComponent("model.obj")
        try Data("export".utf8).write(to: exported)

        let transaction = try fixture.manager.stageDeletion(scanID: scanID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: asset.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: exported.path))

        try transaction.rollback()
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.path))
    }

    func testStorageAuditAndCleanupNeverRemoveLiveScan() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let liveID = UUID()
        let orphanID = UUID()
        let liveDirectory = try fixture.store.directory(for: liveID)
        let orphanDirectory = try fixture.store.directory(for: orphanID)
        try Data(repeating: 1, count: 4_096).write(to: liveDirectory.appendingPathComponent("live.usdz"))
        try Data(repeating: 2, count: 8_192).write(to: orphanDirectory.appendingPathComponent("orphan.usdz"))
        let orphanExport = fixture.exportRoot.appendingPathComponent(orphanID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: orphanExport, withIntermediateDirectories: true)
        try Data(repeating: 3, count: 2_048).write(to: orphanExport.appendingPathComponent("orphan.obj"))

        let audit = try fixture.manager.auditStorage(liveScanIDs: [liveID])
        XCTAssertEqual(audit.itemCount, 2)
        XCTAssertGreaterThan(audit.totalBytes, 0)
        XCTAssertFalse(audit.orphanURLs.contains(liveDirectory))

        try fixture.manager.clean(audit, liveScanIDs: [liveID])
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanExport.path))
    }

    func testRawRetentionRemovesOnlyOldCompletedArchives() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let old = try completedScan(in: fixture, age: 100)
        let recent = try completedScan(in: fixture, age: 10)
        var didSave = false

        let removed = try fixture.manager.applyRawArchiveRetention(
            to: [old.scan, recent.scan],
            keepLatest: 1
        ) {
            didSave = true
        }

        XCTAssertEqual(removed, 1)
        XCTAssertTrue(didSave)
        XCTAssertNil(old.scan.rawArchiveURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.raw.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.model.path))
        XCTAssertEqual(recent.scan.rawArchiveURL, recent.raw)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.raw.path))
        XCTAssertNil(try fixture.store.loadManifest(for: old.scan.id).rawArchiveURL)
    }

    func testRawRetentionRollsBackFilesAndManifestWhenSaveFails() throws {
        enum SaveFailure: Error { case rejected }
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let value = try completedScan(in: fixture, age: 100)

        XCTAssertThrowsError(
            try fixture.manager.applyRawArchiveRetention(to: [value.scan], keepLatest: 0) {
                throw SaveFailure.rejected
            }
        )
        XCTAssertEqual(value.scan.rawArchiveURL, value.raw)
        XCTAssertTrue(FileManager.default.fileExists(atPath: value.raw.path))
        XCTAssertEqual(try fixture.store.loadManifest(for: value.scan.id).rawArchiveURL, value.raw)
    }

    private func completedScan(
        in fixture: Fixture,
        age: TimeInterval
    ) throws -> (scan: ScanSession, raw: URL, model: URL) {
        let scan = ScanSession(
            creationDate: Date().addingTimeInterval(-age),
            captureMode: .object,
            captureStatus: .captured,
            computeStatus: .completed
        )
        let directory = try fixture.store.directory(for: scan.id)
        let raw = directory.appendingPathComponent("raw.zip")
        let model = directory.appendingPathComponent("model.usdz")
        try Data("raw".utf8).write(to: raw)
        try Data("model".utf8).write(to: model)
        scan.rawArchiveURL = raw
        scan.sourceModelURL = model
        scan.usdzFileURL = model
        try fixture.store.writeManifest(try fixture.store.manifest(for: scan))
        return (scan, raw, model)
    }

    func testDeletionCommitRemovesStagedAssetsAndExports() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let scanID = UUID()
        let scanDirectory = try fixture.store.directory(for: scanID)
        try Data("model".utf8).write(to: scanDirectory.appendingPathComponent("model.usdz"))
        let exportDirectory = fixture.exportRoot.appendingPathComponent(scanID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        try Data("export".utf8).write(to: exportDirectory.appendingPathComponent("model.obj"))

        let transaction = try fixture.manager.stageDeletion(scanID: scanID)
        try transaction.commit()

        XCTAssertFalse(FileManager.default.fileExists(atPath: scanDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportDirectory.path))
        XCTAssertTrue(transaction.moves.allSatisfy { !FileManager.default.fileExists(atPath: $0.staged.path) })
        XCTAssertThrowsError(try transaction.rollback())
    }
}

private struct Fixture {
    let root: URL
    let store: ScanAssetStore
    let exportRoot: URL
    let manager: ScanLifecycleManager

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-lifecycle-\(UUID())", isDirectory: true)
        let assets = root.appendingPathComponent("Scans", isDirectory: true)
        exportRoot = root.appendingPathComponent("Exports", isDirectory: true)
        store = try ScanAssetStore(rootDirectory: assets)
        manager = try ScanLifecycleManager(assetStore: store, exportRoot: exportRoot)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
