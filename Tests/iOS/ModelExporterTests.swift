import XCTest
@testable import ThreeDSeen

final class ModelExporterTests: XCTestCase {

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

    func testExportSampleWritesRealFiles() throws {
        let exporter = ModelExporter()
        for format in [ExportFormat.obj, .stl, .ply] {
            let url = try exporter.exportSample(to: format)
            defer { try? FileManager.default.removeItem(at: url) }
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(format) not written")
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            XCTAssertGreaterThan(size, 0, "\(format) file is empty")
            XCTAssertEqual(url.pathExtension, format.fileExtension)
        }
    }

    func testUnsupportedFormatThrows() {
        XCTAssertThrowsError(try ModelExporter().exportSample(to: .glb))
        XCTAssertThrowsError(try ModelExporter().exportSample(to: .fbx))
    }
}
