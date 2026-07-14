import XCTest
import CoreGraphics
import ImageIO
@testable import ThreeDSeen

final class ModelExporterTests: XCTestCase {

    func testCaptureArchiveInspectorCountsNestedImageFrames() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureArchiveInspectorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("frames", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try writePNG(red: 128, green: 128, blue: 128, to: nested.appendingPathComponent("frame-0001.JPG"))
        try Data([0x00]).write(to: nested.appendingPathComponent("notes.txt"))

        XCTAssertEqual(CaptureArchiveInspector.imageFrameCount(in: root), 1)
        XCTAssertTrue(CaptureArchiveInspector.containsImageFrames(in: root))
    }

    func testCaptureArchiveInspectorRejectsMissingOrEmptyFolders() throws {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureArchiveInspectorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        XCTAssertEqual(CaptureArchiveInspector.imageFrameCount(in: empty), 0)
        XCTAssertFalse(CaptureArchiveInspector.containsImageFrames(in: empty))
        XCTAssertFalse(CaptureArchiveInspector.containsImageFrames(in: empty.appendingPathComponent("missing")))

        try Data("not an image".utf8).write(to: empty.appendingPathComponent("corrupt.jpg"))
        XCTAssertEqual(CaptureArchiveInspector.imageFrameCount(in: empty), 1)
        XCTAssertEqual(CaptureArchiveInspector.decodableImageFrameCount(in: empty), 0)
        XCTAssertFalse(CaptureArchiveInspector.containsImageFrames(in: empty))
    }

    func testCaptureQualityReportCountsMeasuredExposureAndSharpnessWarnings() {
        let report = CaptureQualityAnalyzer.report(
            from: [
                .init(meanLuma: 0.52, edgeContrast: 0.08),
                .init(meanLuma: 0.04, edgeContrast: 0.08),
                .init(meanLuma: 0.96, edgeContrast: 0.08),
                .init(meanLuma: 0.52, edgeContrast: 0.01),
            ],
            totalFrameCount: 4
        )

        XCTAssertEqual(report.totalFrameCount, 4)
        XCTAssertEqual(report.analyzedFrameCount, 4)
        XCTAssertEqual(report.usableFrameCount, 1)
        XCTAssertEqual(report.darkFrameCount, 1)
        XCTAssertEqual(report.brightFrameCount, 1)
        XCTAssertEqual(report.blurryFrameCount, 1)
        XCTAssertEqual(report.warningCount, 3)
        XCTAssertEqual(report.summary, "3 sampled frames need attention")

        let cleanReport = CaptureQualityReport(
            totalFrameCount: 4,
            analyzedFrameCount: 4,
            usableFrameCount: 4,
            darkFrameCount: 0,
            brightFrameCount: 0,
            blurryFrameCount: 0
        )
        XCTAssertEqual(cleanReport.summary, "4 sampled frames passed exposure and sharpness checks")
    }

    func testScanManifestRetainsCaptureQualityReport() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureQualityManifestTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let report = CaptureQualityReport(
            totalFrameCount: 12,
            analyzedFrameCount: 12,
            usableFrameCount: 9,
            darkFrameCount: 1,
            brightFrameCount: 1,
            blurryFrameCount: 1
        )
        let scan = ScanSession(captureMode: .object)
        scan.captureQualityReport = report

        let store = try ScanAssetStore(rootDirectory: root)
        let manifest = try store.manifest(for: scan)

        XCTAssertEqual(manifest.captureQualityReport, report)
    }

    func testScanStoreWritesPortablePathsAndResolvesThem() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortableManifestTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let scan = ScanSession(captureMode: .object)
        let store = try ScanAssetStore(rootDirectory: root)
        let scanDirectory = try store.directory(for: scan.id)
        let modelURL = scanDirectory.appendingPathComponent("model.usdz")
        try Data("model".utf8).write(to: modelURL)
        scan.markComputed(modelURL: modelURL, usdzURL: modelURL)

        try store.writeManifest(try store.manifest(for: scan))

        let manifestData = try Data(contentsOf: store.manifestURL(for: scan.id))
        let manifestText = try XCTUnwrap(String(data: manifestData, encoding: .utf8))
        XCTAssertFalse(manifestText.contains(root.path))
        let loaded = try store.loadManifest(for: scan.id)
        XCTAssertEqual(loaded.sourceModelURL, modelURL)
        XCTAssertEqual(loaded.usdzFileURL, modelURL)
    }

    func testScanStoreRejectsMismatchedManifestWithoutMutatingSession() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManifestIdentityTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let scan = ScanSession(captureMode: .object, tier: "Medium")
        let manifest = ScanAssetManifest(scanID: UUID(), captureMode: .space, detailTier: "Full")
        let store = try ScanAssetStore(rootDirectory: root)

        XCTAssertThrowsError(try store.register(manifest, on: scan))
        XCTAssertEqual(scan.captureMode, .object)
        XCTAssertEqual(scan.tierRaw, "Medium")
    }

    func testCaptureQualityAnalyzerDecodesRetainedPNGs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureQualityAnalyzerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writePNG(red: 0, green: 0, blue: 0, to: root.appendingPathComponent("dark.png"))
        try writePNG(red: 255, green: 255, blue: 255, to: root.appendingPathComponent("bright.png"))

        let report = CaptureQualityAnalyzer.analyze(archive: root)
        let singleSample = CaptureQualityAnalyzer.analyze(archive: root, maximumFrames: 1)

        XCTAssertEqual(report.totalFrameCount, 2)
        XCTAssertEqual(singleSample.totalFrameCount, 2)
        XCTAssertEqual(singleSample.analyzedFrameCount, 1)
        XCTAssertEqual(report.analyzedFrameCount, 2)
        XCTAssertEqual(report.darkFrameCount, 1)
        XCTAssertEqual(report.brightFrameCount, 1)
    }

    func testGeometryInspectorReportsModelIOTriangleCount() throws {
        let facts = try XCTUnwrap(ModelGeometryInspector.inspect(asset: ModelExporter().sampleAsset()))

        XCTAssertGreaterThan(facts.vertexCount, 0)
        XCTAssertGreaterThan(facts.triangleCount, 0)
        XCTAssertEqual(facts.formattedTriangleCount, "8.2K")
    }

    private func writePNG(red: UInt8, green: UInt8, blue: UInt8, to url: URL) throws {
        var pixels: [UInt8] = []
        for _ in 0..<16 {
            pixels.append(contentsOf: [red, green, blue, 255])
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: 4,
                height: 4,
                bitsPerComponent: 8,
                bytesPerRow: 16,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )
        )
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    func testHandoffArchivePackagesCaptureDirectoryAsZip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HandoffArchiveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = root.appendingPathComponent("capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        try writePNG(red: 128, green: 128, blue: 128, to: capture.appendingPathComponent("frame_0001.jpg"))

        let package = try ScanHandoffArchive.package(capture)
        XCTAssertEqual(package.pathExtension, "zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.path))

        let unpacked = root.appendingPathComponent("unpacked", isDirectory: true)
        try FileManager.default.unzipItem(at: package, to: unpacked)
        XCTAssertEqual(CaptureArchiveInspector.imageFrameCount(in: unpacked), 1)
    }

    func testHandoffResourceMetadataRoundTripsEveryCaptureMode() {
        let source = URL(fileURLWithPath: "/tmp/capture-with-hyphens.zip")

        let scanID = UUID()
        for mode in CaptureMode.allCases {
            let metadata = ScanHandoffMetadata(scanID: scanID, captureMode: mode, detailTier: "Full Detail")
            let resourceName = NetworkHandoffManager.handoffResourceName(for: source, metadata: metadata)

            XCTAssertEqual(NetworkHandoffManager.handoffMetadata(from: resourceName), metadata)
            XCTAssertEqual(NetworkHandoffManager.handoffOriginalResourceName(from: resourceName), source.lastPathComponent)
        }
    }

    func testLegacyAutoPilotHandoffMetadataStillDecodes() {
        let resourceName = "3dseen-handoff-auto-pilot-full-capture.zip"

        XCTAssertEqual(
            NetworkHandoffManager.handoffMetadata(from: resourceName),
            ScanHandoffMetadata(captureMode: .autoPilot, detailTier: "Full")
        )
        XCTAssertEqual(NetworkHandoffManager.handoffOriginalResourceName(from: resourceName), "capture.zip")
    }

    func testHandoffArchiveCarriesCaptureQualityReport() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HandoffQualityTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = root.appendingPathComponent("capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        try writePNG(red: 128, green: 128, blue: 128, to: capture.appendingPathComponent("frame_0001.jpg"))
        let report = CaptureQualityReport(
            totalFrameCount: 6,
            analyzedFrameCount: 6,
            usableFrameCount: 5,
            darkFrameCount: 1,
            brightFrameCount: 0,
            blurryFrameCount: 0
        )

        let package = try ScanHandoffArchive.package(capture, captureQualityReport: report)
        let unpacked = root.appendingPathComponent("unpacked", isDirectory: true)
        try FileManager.default.unzipItem(at: package, to: unpacked)

        XCTAssertEqual(ScanHandoffArchive.captureQualityReport(in: unpacked), report)
    }

    func testFileExtensions() {
        XCTAssertEqual(ExportFormat.usdz.fileExtension, "usdz")
        XCTAssertEqual(ExportFormat.usd.fileExtension, "usdc")
        XCTAssertEqual(ExportFormat.obj.fileExtension, "obj")
        XCTAssertEqual(ExportFormat.stl.fileExtension, "stl")
        XCTAssertEqual(ExportFormat.ply.fileExtension, "ply")
        XCTAssertEqual(ExportFormat.glb.fileExtension, "glb")
        XCTAssertEqual(ExportFormat.fbx.fileExtension, "fbx")
    }

    func testModelIONativeFlags() {
        XCTAssertTrue(ExportFormat.obj.isModelIONative)
        XCTAssertTrue(ExportFormat.stl.isModelIONative)
        XCTAssertTrue(ExportFormat.ply.isModelIONative)
        XCTAssertFalse(ExportFormat.glb.isModelIONative)
        XCTAssertFalse(ExportFormat.fbx.isModelIONative)
    }

    @MainActor
    func testIsolatedExportRequestAndProvenanceSaveAreDurable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("isolated-export-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ScanAssetStore(rootDirectory: root.appendingPathComponent("scans"))
        let scan = ScanSession(captureMode: .object, name: "Durable Scan")
        let scanDirectory = try store.directory(for: scan.id)
        let source = scanDirectory.appendingPathComponent("model.usdz")
        try Data("usdz fixture".utf8).write(to: source)
        scan.markComputed(modelURL: source, usdzURL: source)
        try store.writeManifest(try store.manifest(for: scan))
        let request = ModelExportRequest(
            scanID: scan.id,
            sourceModelURL: source,
            fileBaseName: scan.exportFileBaseName,
            measurements: scan.measurements
        )
        let output = try ModelExporter().export(
            request: request,
            to: .usdz,
            outputDirectory: root.appendingPathComponent("exports")
        )
        XCTAssertNil(scan.lastExportedURL, "Background-safe request must not mutate SwiftData state")
        var didSave = false

        try ScanExportProvenanceRecorder.record(output, on: scan, assetStore: store) {
            didSave = true
        }

        XCTAssertTrue(didSave)
        XCTAssertEqual(scan.lastExportedURL, output)
        let manifest = try store.loadManifest(for: scan.id)
        XCTAssertEqual(manifest.lastExportedFileName, output.lastPathComponent)
        XCTAssertNotNil(manifest.lastExportedAt)
    }

    @MainActor
    func testExportProvenanceRollsBackWhenContextSaveFails() throws {
        enum SaveFailure: Error { case rejected }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-rollback-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ScanAssetStore(rootDirectory: root.appendingPathComponent("scans"))
        let scan = ScanSession(captureMode: .object)
        _ = try store.directory(for: scan.id)
        try store.writeManifest(try store.manifest(for: scan))
        let output = root.appendingPathComponent("model.usdz")
        try Data("output".utf8).write(to: output)

        XCTAssertThrowsError(
            try ScanExportProvenanceRecorder.record(output, on: scan, assetStore: store) {
                throw SaveFailure.rejected
            }
        )
        XCTAssertNil(scan.lastExportedURL)
        XCTAssertTrue(scan.lastExportedFileName.isEmpty)
        XCTAssertNil(scan.lastExportedAt)
        XCTAssertNil(try store.loadManifest(for: scan.id).lastExportedAt)
    }

    func testExportSampleWritesRealFiles() throws {
        let exporter = ModelExporter()
        for format in [ExportFormat.usd, .obj, .stl, .ply] {
            let url = try exporter.exportSample(to: format, named: "export-test-\(UUID())")
            defer {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("mtl"))
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(format) not written")
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            XCTAssertGreaterThan(size, 0, "\(format) file is empty")
            XCTAssertEqual(url.pathExtension, format.fileExtension)
        }
    }

    func testOBJExportCommitsReferencedMaterialSidecar() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OBJSidecarTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let exporter = ModelExporter()
        let output = root.appendingPathComponent("model.obj")

        try exporter.export(asset: exporter.sampleAsset(), to: .obj, outputURL: output)

        let contents = try String(contentsOf: output)
        XCTAssertTrue(contents.contains("mtllib model.mtl"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("model.mtl").path))
    }

    func testUnsupportedFormatThrows() {
        XCTAssertThrowsError(try ModelExporter().exportSample(to: .glb))
        XCTAssertThrowsError(try ModelExporter().exportSample(to: .fbx))
    }
}

extension ModelExporterTests {
    func testLibraryActionsReflectPersistedLifecycleState() throws {
        let draft = ScanSession(captureMode: .object, captureStatus: .draft)
        let retained = ScanSession(
            captureMode: .object,
            captureStatus: .packaged,
            computeStatus: .notStarted
        )
        let offloaded = ScanSession(
            captureMode: .landscape,
            captureStatus: .packaged,
            computeStatus: .offloaded
        )
        let failed = ScanSession(
            captureMode: .object,
            captureStatus: .packaged,
            computeStatus: .failed
        )
        let missingCompletedModel = ScanSession(
            captureMode: .space,
            captureStatus: .captured,
            computeStatus: .completed
        )
        let modelURL = FileManager.default.temporaryDirectory.appendingPathComponent("library-model-\(UUID()).usdz")
        defer { try? FileManager.default.removeItem(at: modelURL) }
        try Data("model".utf8).write(to: modelURL)
        let completed = ScanSession(
            captureMode: .space,
            usdzFileURL: modelURL,
            captureStatus: .captured,
            computeStatus: .completed
        )

        XCTAssertEqual(ScanItem(draft).primaryAction, .resumeCapture)
        XCTAssertEqual(ScanItem(retained).primaryAction, .resumeReview)
        XCTAssertEqual(ScanItem(offloaded).primaryAction, .resumeCompute)
        XCTAssertEqual(ScanItem(failed).primaryAction, .retryCompute)
        XCTAssertEqual(ScanItem(missingCompletedModel).primaryAction, .retryCompute)
        XCTAssertFalse(ScanItem(missingCompletedModel).canExport)
        XCTAssertEqual(ScanItem(completed).primaryAction, .view)
        XCTAssertTrue(ScanItem(completed).canExport)
    }

    func testLibrarySummaryUsesPersistedScanFacts() {
        let sessions = [
            ScanSession(captureMode: .object, sizeMB: 120, computeStatus: .completed),
            ScanSession(captureMode: .space, sizeMB: 880, computeStatus: .queued),
            ScanSession(captureMode: .object, sizeMB: 0, computeStatus: .failed),
            ScanSession(captureMode: .landscape, sizeMB: -4, computeStatus: .notStarted),
        ]

        let summary = ScanLibrarySummary(sessions: sessions)

        XCTAssertEqual(summary.scanCount, 4)
        XCTAssertEqual(summary.objectCount, 2)
        XCTAssertEqual(summary.spaceCount, 1)
        XCTAssertEqual(summary.landscapeCount, 1)
        XCTAssertEqual(summary.totalSizeMB, 1_000)
        XCTAssertEqual(summary.pendingComputeCount, 3)
    }

    func testLocalComputeRequestUsesPersistedCaptureDirectory() throws {
        let rawArchiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("3dseen-materializer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rawArchiveURL, withIntermediateDirectories: true)
        try writePNG(red: 128, green: 128, blue: 128, to: rawArchiveURL.appendingPathComponent("frame_0001.jpg"))
        defer { try? FileManager.default.removeItem(at: rawArchiveURL) }

        let scan = ScanSession(
            creationDate: Date(timeIntervalSince1970: 0),
            captureMode: .object,
            name: "Materializer Fixture",
            sizeMB: 12,
            tier: "Medium",
            tone: "bone",
            triangles: "Pending",
            rawArchiveURL: rawArchiveURL,
            captureStatus: .packaged,
            computeStatus: .notStarted,
            frameCount: 42,
            coveragePercent: 87,
            weakSpotCount: 1
        )

        let outputDirectory = rawArchiveURL.appendingPathComponent("output", isDirectory: true)
        let request = try ScanLocalComputeRequest(scan: scan, outputDirectory: outputDirectory)

        XCTAssertEqual(request.inputFolder, rawArchiveURL)
        XCTAssertEqual(request.outputURL, outputDirectory.appendingPathComponent("model.usdz"))
        XCTAssertEqual(request.detailTier, "Medium")
    }

    func testLocalComputeRequestRejectsMissingCaptureArchive() {
        let scan = ScanSession(captureMode: .object)

        XCTAssertThrowsError(try ScanLocalComputeRequest(scan: scan, outputDirectory: FileManager.default.temporaryDirectory))
    }

    func testLocalComputeRequestRejectsEmptyCaptureArchive() throws {
        let emptyArchive = FileManager.default.temporaryDirectory
            .appendingPathComponent("3dseen-empty-capture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyArchive, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyArchive) }
        let scan = ScanSession(captureMode: .object, rawArchiveURL: emptyArchive)

        XCTAssertThrowsError(try ScanLocalComputeRequest(scan: scan, outputDirectory: FileManager.default.temporaryDirectory))
    }

    func testAssetStoreImportsCaptureIntoScanDirectory() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("3dseen-capture-store-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("frame".utf8).write(to: source.appendingPathComponent("frame_0001.jpg"))
        defer { try? fm.removeItem(at: root) }

        let scanID = UUID()
        let store = try ScanAssetStore(rootDirectory: root.appendingPathComponent("scans", isDirectory: true))
        let imported = try store.importCapture(from: source, for: scanID)

        XCTAssertNotEqual(imported, source)
        XCTAssertTrue(fm.fileExists(atPath: imported.appendingPathComponent("frame_0001.jpg").path))
    }

    func testSessionDoesNotAdvertiseMissingModelAsRenderable() {
        let missingModel = FileManager.default.temporaryDirectory
            .appendingPathComponent("3dseen-missing-model-\(UUID().uuidString).usdz")
        let scan = ScanSession(captureMode: .object, sourceModelURL: missingModel, computeStatus: .completed)

        XCTAssertFalse(scan.hasRenderableAsset)
    }

    func testSessionPersistsModelMeasurements() {
        let scan = ScanSession(captureMode: .object)
        let measurement = ScanMeasurement(
            start: .init(x: 0, y: 0, z: 0),
            end: .init(x: 0.12, y: 0, z: 0),
            label: "Width"
        )

        scan.measurements = [measurement]

        XCTAssertEqual(scan.measurements, [measurement])
        XCTAssertEqual(scan.measurements[0].meters, 0.12, accuracy: 0.0001)
    }

    func testMeasurementExporterWritesCSV() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("measurement-export-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let measurement = ScanMeasurement(
            start: .init(x: 0, y: 0, z: 0),
            end: .init(x: 0.25, y: 0, z: 0),
            label: "Width"
        )

        let output = try MeasurementExporter().exportCSV([measurement], named: "test-scan", to: root)

        XCTAssertEqual(output.lastPathComponent, "test-scan-measurements.csv")
        XCTAssertTrue(try String(contentsOf: output).contains("Width,0.250000,25.000,9.843"))
    }

    func testResultPackageRoundTripsManifestAndModel() throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("3dseen-result-package-test-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let rawArchiveURL = work.appendingPathComponent("raw", isDirectory: true)
        try fm.createDirectory(at: rawArchiveURL, withIntermediateDirectories: true)
        let modelURL = work.appendingPathComponent("model.stl")
        let exporter = ModelExporter()
        try exporter.export(asset: exporter.sampleAsset(), to: .stl, outputURL: modelURL)
        let previewURL = work.appendingPathComponent("geometry-preview.ply")
        let geometryPLY = """
        ply
        format ascii 1.0
        element vertex 2
        property float x
        property float y
        property float z
        end_header
        0 0 0
        1 0 0
        """
        try Data(geometryPLY.utf8).write(to: previewURL)

        let scan = ScanSession(
            captureMode: .object,
            rawArchiveURL: rawArchiveURL,
            sourceModelURL: modelURL,
            previewPLYURL: previewURL,
            computeStatus: .completed,
            frameCount: 12,
            coveragePercent: 91,
            weakSpotCount: 2
        )
        let manifest = try ScanAssetStore().manifest(for: scan)

        let package = ScanResultPackage()
        let zipURL = try package.write(output: modelURL, manifest: manifest)
        XCTAssertEqual(zipURL.pathExtension, "zip")

        let unpackDir = work.appendingPathComponent("unpacked", isDirectory: true)
        let contents = try package.unpack(zipURL, to: unpackDir)
        XCTAssertEqual(contents.manifest.scanID, scan.id)
        XCTAssertEqual(contents.manifest.frameCount, 12)
        XCTAssertNotNil(ModelGeometryInspector.inspect(modelURL: contents.modelURL))
        guard let unpackedPreview = contents.previewPLYURL else {
            return XCTFail("Expected package preview PLY")
        }
        XCTAssertEqual(try String(contentsOf: unpackedPreview), geometryPLY)
    }

    func testResultPackageRejectsCorruptModelPayload() throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("corrupt-result-test-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let modelURL = work.appendingPathComponent("model.stl")
        try Data("not model geometry".utf8).write(to: modelURL)
        let manifest = ScanAssetManifest(scanID: UUID(), captureMode: .object, detailTier: "Medium")
        let packageURL = try ScanResultPackage().write(output: modelURL, manifest: manifest)

        XCTAssertThrowsError(
            try ScanResultPackage().unpack(
                packageURL,
                to: work.appendingPathComponent("unpacked", isDirectory: true)
            )
        )
    }

    func testResultPackageRetainsTrainedSplatProvenance() throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("trained-package-test-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let modelURL = work.appendingPathComponent("model.stl")
        let previewURL = work.appendingPathComponent("source-trained.ply")
        let exporter = ModelExporter()
        try exporter.export(asset: exporter.sampleAsset(), to: .stl, outputURL: modelURL)
        let splats = GaussianSplatGenerator.splats(fromPoints: [
            (position: SIMD3<Float>(0, 0, 0), color: SIMD3<Float>(0.2, 0.4, 0.6)),
        ])
        try SplatPLYWriter.write(splats, to: previewURL)
        let manifest = ScanAssetManifest(
            scanID: UUID(),
            captureMode: .object,
            detailTier: "Medium",
            sourceModelURL: modelURL,
            previewPLYURL: previewURL,
            previewPLYKind: .trainedSplat
        )

        let zipURL = try ScanResultPackage().write(output: modelURL, manifest: manifest)
        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        let contents = try ScanResultPackage().unpack(zipURL, to: unpacked)

        XCTAssertEqual(contents.manifest.previewPLYKind, .trainedSplat)
        XCTAssertEqual(contents.previewPLYURL?.lastPathComponent, "trained-splat.ply")
        XCTAssertTrue(PLYValidator.isValid(try XCTUnwrap(contents.previewPLYURL), kind: .trainedSplat))
    }

    func testResultPackageImportRejectsMalformedPLY() throws {
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory
            .appendingPathComponent("invalid-ply-package-\(UUID())", isDirectory: true)
        let package = work.appendingPathComponent("package", isDirectory: true)
        try fileManager.createDirectory(at: package, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: work) }
        let exporter = ModelExporter()
        let modelURL = package.appendingPathComponent("model.stl")
        try exporter.export(asset: exporter.sampleAsset(), to: .stl, outputURL: modelURL)
        try Data("ply but not really".utf8).write(to: package.appendingPathComponent("geometry-preview.ply"))
        let manifest = ScanAssetManifest(
            scanID: UUID(),
            captureMode: .object,
            detailTier: "Medium",
            sourceModelURL: modelURL,
            previewPLYURL: package.appendingPathComponent("geometry-preview.ply")
        )
        try JSONEncoder().encode(manifest).write(to: package.appendingPathComponent("manifest.json"))
        let zip = work.appendingPathComponent("malicious.3dseen-result.zip")
        try fileManager.zipItem(at: package, to: zip, shouldKeepParent: false)

        XCTAssertThrowsError(
            try ScanResultPackage().unpack(zip, to: work.appendingPathComponent("unpacked", isDirectory: true))
        )
    }
}
