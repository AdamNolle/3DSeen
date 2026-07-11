import XCTest
import SwiftUI
@testable import ThreeDSeenMac

final class SettingsStoreTests: XCTestCase {

    func testColorSchemeMappingSeam() {
        XCTAssertNil(SettingsStore.colorScheme(for: .system))
        XCTAssertEqual(SettingsStore.colorScheme(for: .light), .light)
        XCTAssertEqual(SettingsStore.colorScheme(for: .dark), .dark)
    }

    func testFreshStoreDefaults() {
        let suite = UserDefaults(suiteName: "SettingsStoreTests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)

        XCTAssertEqual(store.appearance, .system)
        XCTAssertEqual(store.defaultMode, .object)
        XCTAssertEqual(store.qualityTier, .full)
        XCTAssertEqual(store.units, .centimeters)
        XCTAssertFalse(store.gridIsList)
        XCTAssertNil(store.colorScheme)
    }

    func testPersistenceRoundTrip() {
        let suite = UserDefaults(suiteName: "SettingsStoreTests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)
        store.appearance = .dark
        store.defaultMode = .landscape
        store.qualityTier = .reduced
        store.units = .inches
        store.gridIsList = true

        // A second store over the same suite reads the persisted values.
        let reopened = SettingsStore(defaults: suite)
        XCTAssertEqual(reopened.appearance, .dark)
        XCTAssertEqual(reopened.defaultMode, .landscape)
        XCTAssertEqual(reopened.qualityTier, .reduced)
        XCTAssertEqual(reopened.units, .inches)
        XCTAssertTrue(reopened.gridIsList)
        XCTAssertEqual(reopened.colorScheme, .dark)
    }

    func testScanAssetManifestRoundTripUpdatesSession() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanAssetStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ScanAssetStore(rootDirectory: root)
        let session = ScanSession(captureMode: .object, name: "Ceramic Bust")
        let modelURL = try store.directory(for: session.id).appendingPathComponent("model.usdz")
        try Data("usdz".utf8).write(to: modelURL)
        let manifest = ScanAssetManifest(
            scanID: session.id,
            captureMode: .object,
            detailTier: "Full",
            sourceModelURL: modelURL,
            usdzFileURL: modelURL,
            frameCount: 340,
            coveragePercent: 92,
            weakSpotCount: 3
        )

        try store.register(manifest, on: session)
        let reopened = try store.loadManifest(for: session.id)

        XCTAssertEqual(reopened, manifest)
        XCTAssertEqual(session.captureStatus, .needsRetake)
        XCTAssertEqual(session.displayModelURL, modelURL)
        XCTAssertEqual(session.frameCount, 340)
        XCTAssertEqual(session.coveragePercent, 92)
        XCTAssertEqual(session.weakSpotCount, 3)
    }

    func testModelExporterUsesSessionAssetAndRecordsOutput() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelExporterSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let source = root.appendingPathComponent("source.usdz")
        try Data("usdz".utf8).write(to: source)
        let session = ScanSession(captureMode: .object, name: "Celestial Bust!", usdzFileURL: source)

        let output = try ModelExporter().export(session: session, to: .usdz, outputDirectory: root)

        XCTAssertEqual(output.lastPathComponent, "celestial-bust.usdz")
        XCTAssertEqual(session.lastExportedURL, output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }

    func testModelExporterRejectsSessionWithoutAsset() {
        let session = ScanSession(captureMode: .object)

        XCTAssertThrowsError(try ModelExporter().export(session: session, to: .usdz)) { error in
            guard case ExportError.noSourceAsset = error else {
                return XCTFail("Expected noSourceAsset, got \(error)")
            }
        }
    }
}
