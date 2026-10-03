import XCTest
#if os(macOS)
@testable import ThreeDSeenMac
#else
@testable import ThreeDSeen
#endif

final class MeasurementExporterTests: XCTestCase {
    @MainActor
    func testMeasurementsPersistToManifestAndRollbackWhenDatabaseSaveFails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("measurement-save-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ScanAssetStore(rootDirectory: root)
        let scan = ScanSession(captureMode: .object)
        let measurement = ScanMeasurement(
            start: ScanMeasurementPoint(x: 0, y: 0, z: 0),
            end: ScanMeasurementPoint(x: 1, y: 0, z: 0), label: "Width"
        )
        try ScanMeasurementRecorder.replace([measurement], on: scan, assetStore: store, save: {})
        XCTAssertEqual(try store.loadManifest(for: scan.id).measurements, [measurement])
        XCTAssertThrowsError(try ScanMeasurementRecorder.replace([], on: scan, assetStore: store) {
            throw CocoaError(.fileWriteNoPermission)
        })
        XCTAssertEqual(scan.measurements, [measurement])
        XCTAssertEqual(try store.loadManifest(for: scan.id).measurements, [measurement])
        try ScanMeasurementRecorder.replace([], on: scan, assetStore: store, save: {})
        XCTAssertEqual(try store.loadManifest(for: scan.id).measurements, [])
    }

    func testUnsafeScanNamesCannotEscapeMeasurementExportDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("measurement-export-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let output = try MeasurementExporter().exportCSV([], named: "../../other/Scan", to: root)
        XCTAssertEqual(output.deletingLastPathComponent().standardizedFileURL, root.standardizedFileURL)
        XCTAssertEqual(output.lastPathComponent, "other-scan-measurements.csv")
        XCTAssertEqual(ScanExportLocation.fileBaseName(for: String(repeating: "A", count: 300), fallback: "scan").count, 80)
        XCTAssertEqual(ScanExportLocation.fileBaseName(for: ".../", fallback: "scan"), "scan")
    }

    func testFormattedExportDirectorySeparatesFormatsAndSupportsMacDestination() {
        let scanID = UUID()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("3DSeen-format-export-tests", isDirectory: true)

        XCTAssertEqual(
            ScanExportLocation.formattedDirectory(for: scanID, format: .usdz, under: root),
            root.appendingPathComponent(scanID.uuidString, isDirectory: true)
                .appendingPathComponent("usdz", isDirectory: true)
        )
        XCTAssertNotEqual(
            ScanExportLocation.formattedDirectory(for: scanID, format: .usdz, under: root),
            ScanExportLocation.formattedDirectory(for: scanID, format: .obj, under: root)
        )
    }

    func testCSVQuotesCarriageReturnsCommasAndQuotes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("measurement-csv-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let measurements = [ScanMeasurement(
            start: ScanMeasurementPoint(x: 0, y: 0, z: 0),
            end: ScanMeasurementPoint(x: 1, y: 0, z: 0),
            label: "Width\r\"left,right\""
        )]
        let output = try MeasurementExporter().exportCSV(measurements, named: "Scan", to: root)
        let text = try String(contentsOf: output)
        XCTAssertTrue(text.contains("\"Width\r\"\"left,right\"\"\",1.000000,"))
    }
}
