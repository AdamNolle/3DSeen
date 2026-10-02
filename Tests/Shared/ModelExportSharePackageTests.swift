import XCTest
import ZIPFoundation
#if os(macOS)
@testable import ThreeDSeenMac
#else
@testable import ThreeDSeen
#endif

final class ModelExportSharePackageTests: XCTestCase {
    func testSelfContainedModelWithMeasurementsKeepsDirectSharing() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = root.appendingPathComponent("model.usdz")
        let measurements = root.appendingPathComponent("measurements.csv")
        try Data("model".utf8).write(to: model)
        try Data("distance\n1".utf8).write(to: measurements)
        XCTAssertNil(try ModelExportSharePackage.prepare(for: model, measurementURL: measurements))
    }

    func testPackageReplacesPreviousContentsAndOmitsObsoleteMeasurements() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("obj", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = directory.appendingPathComponent("model.obj")
        let material = directory.appendingPathComponent("model.mtl")
        let measurements = directory.appendingPathComponent("measurements.csv")
        try Data("mtllib model.mtl".utf8).write(to: model)
        try Data("newmtl captured".utf8).write(to: material)
        try Data("distance\n1".utf8).write(to: measurements)
        let first = try XCTUnwrap(ModelExportSharePackage.prepare(for: model, measurementURL: measurements))
        XCTAssertNotNil(try Archive(url: first, accessMode: .read)["measurements.csv"])
        try Data("updated model".utf8).write(to: model)
        let second = try XCTUnwrap(ModelExportSharePackage.prepare(for: model, measurementURL: nil))
        XCTAssertEqual(first, second)
        let unpacked = root.appendingPathComponent("unpacked", isDirectory: true)
        try FileManager.default.unzipItem(at: second, to: unpacked)
        XCTAssertEqual(try String(contentsOf: unpacked.appendingPathComponent("model.obj")), "updated model")
        XCTAssertTrue(FileManager.default.fileExists(atPath: unpacked.appendingPathComponent("model.mtl").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: unpacked.appendingPathComponent("measurements.csv").path))
    }

    func testPackageDoesNotCollectOtherFormatsOrSourceFrames() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("obj", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = directory.appendingPathComponent("model.obj")
        try Data("mtllib model.mtl".utf8).write(to: model)
        try Data("newmtl captured".utf8).write(to: directory.appendingPathComponent("model.mtl"))
        try Data("source".utf8).write(to: root.appendingPathComponent("source-frame.jpg"))
        try Data("other format".utf8).write(to: root.appendingPathComponent("model.usdc"))
        let package = try XCTUnwrap(ModelExportSharePackage.prepare(for: model, measurementURL: nil))
        let archive = try Archive(url: package, accessMode: .read)
        XCTAssertEqual(Set(archive.map(\.path)), ["model.obj", "model.mtl"])
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("export-share-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
