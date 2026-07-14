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
        XCTAssertEqual(store.defaultMode, .autoPilot)
        XCTAssertEqual(store.qualityTier, .full)
        XCTAssertEqual(store.units, .centimeters)
        XCTAssertFalse(store.gridIsList)
        XCTAssertTrue(store.thermalProtectionEnabled)
        XCTAssertTrue(store.autoSelectTrustedMac)
        XCTAssertEqual(store.rawArchiveRetention, .keepAll)
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
        store.thermalProtectionEnabled = false
        store.autoSelectTrustedMac = false
        store.rawArchiveRetention = .latest5

        // A second store over the same suite reads the persisted values.
        let reopened = SettingsStore(defaults: suite)
        XCTAssertEqual(reopened.appearance, .dark)
        XCTAssertEqual(reopened.defaultMode, .landscape)
        XCTAssertEqual(reopened.qualityTier, .reduced)
        XCTAssertEqual(reopened.units, .inches)
        XCTAssertTrue(reopened.gridIsList)
        XCTAssertFalse(reopened.thermalProtectionEnabled)
        XCTAssertFalse(reopened.autoSelectTrustedMac)
        XCTAssertEqual(reopened.rawArchiveRetention, .latest5)
        XCTAssertEqual(reopened.rawArchiveRetention.limit, 5)
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

    func testVersionedManifestPreservesLifecycleAndDisplayMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanManifestV2Tests-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ScanAssetStore(rootDirectory: root)
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let exported = Date(timeIntervalSince1970: 1_700_000_100)
        let source = ScanSession(
            creationDate: created,
            captureMode: .landscape,
            name: "Garden Arch",
            sizeMB: 412,
            tier: "Full",
            tone: "slate",
            triangles: "1.2M",
            captureStatus: .packaged,
            computeStatus: .offloaded
        )
        source.measurements = [
            ScanMeasurement(
                start: ScanMeasurementPoint(x: 0, y: 0, z: 0),
                end: ScanMeasurementPoint(x: 1, y: 0, z: 0),
                label: "Width"
            )
        ]
        source.appliedMaterialRaw = "stone"
        source.lastExportedFileName = "garden-arch.obj"
        source.lastExportedAt = exported

        let manifest = try store.manifest(for: source)
        try store.writeManifest(manifest)
        let reopened = try store.loadManifest(for: source.id)
        let destination = ScanSession(id: source.id, captureMode: .object)
        destination.apply(manifest: reopened)

        XCTAssertEqual(reopened.schemaVersion, ScanAssetManifest.currentSchemaVersion)
        XCTAssertEqual(destination.name, "Garden Arch")
        XCTAssertEqual(destination.creationDate, created)
        XCTAssertEqual(destination.sizeMB, 412)
        XCTAssertEqual(destination.tierRaw, "Full")
        XCTAssertEqual(destination.toneRaw, "slate")
        XCTAssertEqual(destination.triangles, "1.2M")
        XCTAssertEqual(destination.captureStatus, .packaged)
        XCTAssertEqual(destination.computeStatus, .offloaded)
        XCTAssertEqual(destination.measurements.first?.label, "Width")
        XCTAssertEqual(destination.appliedMaterialRaw, "stone")
        XCTAssertEqual(destination.lastExportedFileName, "garden-arch.obj")
        XCTAssertEqual(destination.lastExportedAt, exported)
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
        XCTAssertEqual(session.lastExportedFileName, "celestial-bust.usdz")
        XCTAssertNotNil(session.lastExportedAt)
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
