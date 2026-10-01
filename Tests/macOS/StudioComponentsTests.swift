import XCTest
import SwiftUI
import AppKit
@testable import ThreeDSeenMac

final class StudioComponentsTests: XCTestCase {

    @MainActor
    func testMacPanesRenderAtMinimumWindowSize() throws {
        let size = NSSize(width: 1040, height: 680)
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("mac-render-\(UUID())", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let populatedStore = try ScanAssetStore(rootDirectory: root.appendingPathComponent("populated"))
        let emptyStore = try ScanAssetStore(rootDirectory: root.appendingPathComponent("empty"))
        let scanID = UUID()
        let retained = try populatedStore.directory(for: scanID).appendingPathComponent("model.usda")
        try Data("""
        #usda 1.0
        (defaultPrim = "Triangle")
        def Mesh "Triangle" {
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1, 2]
            point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
        }
        """.utf8).write(to: retained)
        try populatedStore.writeManifest(ScanAssetManifest(
            scanID: scanID, captureMode: .object, detailTier: "Full", sourceModelURL: retained,
            usdzFileURL: retained, displayName: "A long descriptive model name for layout verification"
        ))
        let suite = "mac-render-settings-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for dark in [false, true] {
        for populated in [false, true] {
        let settings = SettingsStore(defaults: defaults)
        settings.appearance = dark ? .dark : .light
        let coordinator = ComputeCoordinator(
            credentialStore: InMemoryPairingCredentialStore(), assetStore: populated ? populatedStore : emptyStore
        )
        if populated { coordinator.selectScan(scanID) }
        for section in MacSection.allCases {
            let nav = MacNav()
            nav.section = section
            let host = NSHostingView(
                rootView: ContentView(nav: nav, compute: coordinator, settings: settings)
                    .environmentObject(ProcessingStateMachine())
                    .frame(width: size.width, height: size.height)
            )
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(
                contentRect: host.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            window.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))

            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = NSImage(size: size)
            image.addRepresentation(bitmap)
            XCTAssertEqual(image.size.width, 1040, accuracy: 1)
            XCTAssertEqual(image.size.height, 680, accuracy: 1)
            var sampledColors = Set<String>()
            for y in stride(from: 20, to: Int(size.height), by: 40) {
                for x in stride(from: 20, to: Int(size.width), by: 40) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    sampledColors.insert(
                        "\(Int(color.redComponent * 255))-\(Int(color.greenComponent * 255))-" +
                        "\(Int(color.blueComponent * 255))-\(Int(color.alphaComponent * 255))"
                    )
                }
            }
            XCTAssertGreaterThan(sampledColors.count, 3, "\(section.rawValue) rendered as a blank or flat image")

            let attachment = XCTAttachment(image: image)
            attachment.name = "Mac \(section.rawValue.capitalized) - \(dark ? "dark" : "light") \(populated ? "selected" : "empty") - 1040x680"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.orderOut(nil)
        }
        }
        }
    }

    @MainActor
    func testMacMeasurementsPersistDeleteAndExportCSV() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-measurements-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ScanAssetStore(rootDirectory: root.appendingPathComponent("scans"))
        let scanID = UUID()
        let directory = try store.directory(for: scanID)
        let modelURL = directory.appendingPathComponent("model.usdz")
        try Data("model".utf8).write(to: modelURL)
        try store.writeManifest(ScanAssetManifest(
            scanID: scanID,
            captureMode: .object,
            detailTier: "Full",
            sourceModelURL: modelURL,
            usdzFileURL: modelURL,
            displayName: "Measured Object"
        ))
        let coordinator = ComputeCoordinator(
            credentialStore: InMemoryPairingCredentialStore(),
            assetStore: store
        )
        coordinator.reloadLibrary()
        let measurement = ScanMeasurement(
            start: ScanMeasurementPoint(x: 0, y: 0, z: 0),
            end: ScanMeasurementPoint(x: 0.5, y: 0, z: 0),
            label: "Width"
        )

        try coordinator.addMeasurement(measurement, to: scanID)
        XCTAssertEqual(try store.loadManifest(for: scanID).measurements, [measurement])
        let csv = try coordinator.exportMeasurements(for: scanID, to: root.appendingPathComponent("exports"))
        XCTAssertTrue(try String(contentsOf: csv).contains("Width,0.500000"))

        try coordinator.removeMeasurement(measurement.id, from: scanID)
        XCTAssertEqual(try store.loadManifest(for: scanID).measurements, [])
        try coordinator.recordExport(csv, for: scanID)
        let exportedManifest = try store.loadManifest(for: scanID)
        XCTAssertEqual(exportedManifest.lastExportedFileName, csv.lastPathComponent)
        XCTAssertNotNil(exportedManifest.lastExportedAt)
        let reopened = ComputeCoordinator(credentialStore: InMemoryPairingCredentialStore(), assetStore: store)
        XCTAssertEqual(reopened.libraryScans.first?.manifest.lastExportedFileName, csv.lastPathComponent)
    }

    func testNativeExportsFromUSDAContainRealGeometry() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("mac-native-export-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source.usda")
        try Data("""
        #usda 1.0
        (defaultPrim = "Triangle")
        def Mesh "Triangle" {
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1, 2]
            point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
        }
        """.utf8).write(to: source)
        for format in [ExportFormat.usd, .obj, .stl, .ply] {
            let output = root.appendingPathComponent("output").appendingPathExtension(format.fileExtension)
            do {
                try ModelExporter().export(sourceModel: source, to: format, outputURL: output)
                XCTAssertNotNil(ModelGeometryInspector.inspect(modelURL: output), "\(format) must retain mesh geometry")
            } catch { XCTFail("\(format) export failed: \(error)") }
        }
    }

    func testSplitPaneLeftWidthHonorsRatioAndGap() {
        // (1000 - 20) * 0.58 = 568.4
        XCTAssertEqual(StSplitPane<EmptyView, EmptyView>.leftWidth(total: 1000, gap: 20, ratio: 0.58),
                       568.4, accuracy: 0.001)
        // ratio clamps to 0…1 and never goes negative.
        XCTAssertEqual(StSplitPane<EmptyView, EmptyView>.leftWidth(total: 500, gap: 20, ratio: 2),
                       480, accuracy: 0.001)
        XCTAssertEqual(StSplitPane<EmptyView, EmptyView>.leftWidth(total: 500, gap: 20, ratio: -1),
                       0, accuracy: 0.001)
    }

    func testFidelityChartYPositionMonotonicAndBounded() {
        let h: CGFloat = 170
        let low = StFidelityChart.yPosition(psnr: 22, height: h)
        let high = StFidelityChart.yPosition(psnr: 44, height: h)
        // Higher PSNR sits higher on screen (smaller y).
        XCTAssertLessThan(high, low)
        // Both stay inside the plot area (above the baseline at h-28).
        XCTAssertLessThan(low, h - 28 + 1)
        XCTAssertGreaterThan(high, 0)
    }

    func testFidelityChartDefaultTiers() {
        XCTAssertEqual(StFidelityChart.defaultTiers.map(\.name),
                       ["Preview", "Reduced", "Medium", "Full", "Raw"])
        XCTAssertEqual(StFidelityChart.defaultTiers.map(\.psnr), [22, 28, 33, 38, 44])
    }
}
