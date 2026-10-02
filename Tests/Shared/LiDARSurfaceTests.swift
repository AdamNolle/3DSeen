import XCTest
import ModelIO
import SceneKit
import ImageIO
import UniformTypeIdentifiers
import ZIPFoundation
import simd
#if os(macOS)
@testable import ThreeDSeenMac
#else
@testable import ThreeDSeen
#endif

final class LiDARSurfaceTests: XCTestCase {
    func testProjectionUsesCameraIntrinsicsAndUnrotatedImageCoordinates() throws {
        let camera = camera(depth: 2)
        let center = try XCTUnwrap(camera.project(SIMD3(0, 0, -2)))
        XCTAssertEqual(center.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.0001)
        let corner = try XCTUnwrap(camera.project(SIMD3(0.5, 0.5, -2)))
        XCTAssertEqual(corner.x, 0.625, accuracy: 0.0001)
        XCTAssertEqual(corner.y, 0.625, accuracy: 0.0001)
    }

    func testTranslatedCameraProjectsWorldGeometryInItsOwnCoordinateSystem() throws {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(1, 0, 0, 1)
        let camera = camera(depth: 2, worldToCamera: transform.inverse)
        let projected = try XCTUnwrap(camera.project(SIMD3(1, 0, -2)))
        XCTAssertEqual(projected.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(camera.position, SIMD3(1, 0, 0))
    }

    func testOcclusionMissingDepthAndBehindCameraNeverPaintUnrelatedSurfaces() {
        XCTAssertNil(camera(depth: 1).project(SIMD3(0, 0, -2)))
        XCTAssertNil(camera(depth: .nan).project(SIMD3(0, 0, -2)))
        XCTAssertNil(camera(depth: 0).project(SIMD3(0, 0, -2)))
        XCTAssertNil(camera(depth: 2).project(SIMD3(0, 0, 2)))
        XCTAssertNil(camera(depth: 2).project(SIMD3(8, 0, -2)))
    }

    func testExportUsesFartherVisibleCameraWhenClosestViewsFaceAway() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try texture(in: directory)
        var backwards = matrix_identity_float4x4
        backwards.columns.0.x = -1
        backwards.columns.2.z = -1
        var farther = matrix_identity_float4x4
        farther.columns.3.z = 1
        let nearFrame = LiDARTextureFrame(imageURL: image, camera: camera(depth: 2, worldToCamera: backwards))
        let visibleFrame = LiDARTextureFrame(imageURL: image, camera: camera(depth: 3, worldToCamera: farther.inverse))
        let frames = Array(repeating: nearFrame, count: 32) + [visibleFrame]
        let result = try LiDARTextureExporter.export(
            meshes: [meshIncludingUnobservedFace()], frames: frames, to: directory.appendingPathComponent("room.usdz"))
        XCTAssertEqual(result.triangleCount, 2)
        XCTAssertEqual(result.texturedTriangleCount, 1)
    }

    func testExportFindsAlternateViewForOnlyTheOccludedFace() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try texture(in: directory)
        var farther = matrix_identity_float4x4
        farther.columns.3.z = 1
        let nearFrame = LiDARTextureFrame(imageURL: image, camera: camera(depth: 2))
        let alternate = LiDARTextureFrame(imageURL: image, camera: camera(depth: 5, worldToCamera: farther.inverse))
        let result = try LiDARTextureExporter.export(
            meshes: [meshIncludingUnobservedFace()], frames: Array(repeating: nearFrame, count: 32) + [alternate],
            to: directory.appendingPathComponent("room.usdz"))
        XCTAssertEqual(result.triangleCount, 2)
        XCTAssertEqual(result.texturedTriangleCount, 2)
    }

    func testExportEmbedsTextureAndPreservesIrregularAndUnobservedGeometry() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try texture(in: directory)
        let mesh = meshIncludingUnobservedFace()
        let output = directory.appendingPathComponent("space.usdz")
        let result = try LiDARTextureExporter.export(meshes: [mesh], frames: [LiDARTextureFrame(imageURL: image, camera: camera(depth: 2))], to: output)
        XCTAssertEqual(result.triangleCount, 2)
        XCTAssertEqual(result.texturedTriangleCount, 1)
        let facts = try XCTUnwrap(ModelGeometryInspector.inspect(modelURL: output))
        XCTAssertEqual(facts.triangleCount, 2)
        let archive = try Archive(url: output, accessMode: .read)
        XCTAssertTrue(archive.contains { ["png", "jpg", "jpeg"].contains(URL(fileURLWithPath: $0.path).pathExtension.lowercased()) })
        let scene = try SCNScene(url: output, options: nil)
        var materialNames: [String] = []
        scene.rootNode.enumerateChildNodes { node, _ in
            materialNames.append(contentsOf: node.geometry?.materials.compactMap(\.name) ?? [])
        }
        XCTAssertTrue(materialNames.contains { $0.hasPrefix("CapturedTexture") })
        XCTAssertTrue(materialNames.contains { $0.hasPrefix("UnobservedSurface") })
        let meshes = MDLAsset(url: output).childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []
        let positions = meshes.flatMap { mesh -> [Float] in
            guard let attribute = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3) else { return [] }
            return (0..<mesh.vertexCount).map { attribute.dataStart.loadUnaligned(fromByteOffset: $0 * attribute.stride + 8, as: Float.self) }
        }
        XCTAssertTrue(positions.contains { abs($0 + 1.95) < 0.001 })
        XCTAssertTrue(positions.contains { abs($0 + 4) < 0.001 })
    }

    func testInvalidMeshAndUnavailableCameraImagesFailWithoutPublishingModel() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try texture(in: directory)
        let frame = LiDARTextureFrame(imageURL: image, camera: camera(depth: 2))
        for mesh in [LiDARSurfaceMesh(vertices: [SIMD3(.nan, 0, -2)], indices: [0, 0, 0]),
                     LiDARSurfaceMesh(vertices: [SIMD3(0, 0, -2)], indices: [0, 1, 0])] {
            XCTAssertThrowsError(try LiDARTextureExporter.export(meshes: [mesh], frames: [frame], to: directory.appendingPathComponent("invalid.usdz")))
        }
        let missing = LiDARTextureFrame(imageURL: directory.appendingPathComponent("missing.jpg"), camera: camera(depth: 2))
        XCTAssertThrowsError(try LiDARTextureExporter.export(meshes: [meshIncludingUnobservedFace()], frames: [missing], to: directory.appendingPathComponent("invalid.usdz")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("invalid.usdz").path))
    }

    func testCancellationDoesNotPublishAnIncompleteModel() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try texture(in: directory)
        let output = directory.appendingPathComponent("cancelled.usdz")
        XCTAssertThrowsError(try LiDARTextureExporter.export(meshes: [meshIncludingUnobservedFace()], frames: [LiDARTextureFrame(imageURL: image, camera: camera(depth: 2))],
                                                            to: output, isCancelled: { true })) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testDurableBundleKeepsModelAndSnapshotsOutsideRemovableSourceArchive() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source")
        let frames = source.appendingPathComponent(LiDARCaptureBundle.framesName)
        let textures = source.appendingPathComponent(LiDARCaptureBundle.texturesName)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: textures, withIntermediateDirectories: true)
        let image = try texture(in: frames)
        try FileManager.default.copyItem(at: image, to: textures.appendingPathComponent("texture_000.png"))
        let result = try LiDARTextureExporter.export(
            meshes: [meshIncludingUnobservedFace()], frames: [LiDARTextureFrame(imageURL: image, camera: camera(depth: 2))],
            to: source.appendingPathComponent(LiDARCaptureBundle.modelName))
        let report = LiDARCaptureReport(schemaVersion: 1, triangleCount: result.triangleCount, texturedTriangleCount: result.texturedTriangleCount, textureFrameCount: 1, textureSnapshotCount: 1)
        try JSONEncoder().encode(report).write(to: source.appendingPathComponent(LiDARCaptureBundle.reportName))
        let store = try ScanAssetStore(rootDirectory: directory.appendingPathComponent("store"))
        let imported = try LiDARCaptureBundle.importCapture(from: source, scanID: UUID(), store: store)
        try FileManager.default.removeItem(at: imported.archiveURL)
        XCTAssertEqual(ModelGeometryInspector.inspect(modelURL: imported.modelURL)?.triangleCount, 2)
        XCTAssertEqual(LiDARCaptureBundle.textureSnapshots(for: imported.modelURL).count, 1)
    }

    #if os(macOS)
    @MainActor
    func testMacImportPreservesTexturedRoomAndUserSelectedSource() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try texture(in: directory)
        let source = directory.appendingPathComponent("shared-room.usdz")
        _ = try LiDARTextureExporter.export(
            meshes: [meshIncludingUnobservedFace()],
            frames: [LiDARTextureFrame(imageURL: image, camera: camera(depth: 2))], to: source)
        let coordinator = ComputeCoordinator(
            credentialStore: InMemoryPairingCredentialStore(),
            assetStore: try ScanAssetStore(rootDirectory: directory.appendingPathComponent("store")),
            remoteJobJournalURL: directory.appendingPathComponent("jobs.json"))
        let scanID = UUID()
        await coordinator.process(archive: source, captureMode: .space,
                                  detailTier: "LiDAR surface", sourceScanID: scanID)
        let scan = try XCTUnwrap(coordinator.libraryScans.first { $0.id == scanID })
        XCTAssertEqual(scan.manifest.detailTier, "LiDAR surface")
        XCTAssertEqual(scan.manifest.captureMode, .space)
        XCTAssertEqual(ModelGeometryInspector.inspect(modelURL: scan.modelURL)?.triangleCount, 2)
        XCTAssertEqual(try Data(contentsOf: scan.modelURL), try Data(contentsOf: source))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    #endif

    private func camera(depth: Float, worldToCamera: simd_float4x4 = matrix_identity_float4x4) -> LiDARTextureCamera {
        LiDARTextureCamera(worldToCamera: worldToCamera,
                           intrinsics: simd_float3x3(columns: (SIMD3(100, 0, 0), SIMD3(0, 100, 0), SIMD3(100, 100, 1))),
                           imageWidth: 200, imageHeight: 200, depthWidth: 4, depthHeight: 4,
                           depths: [Float](repeating: depth, count: 16))
    }

    private func meshIncludingUnobservedFace() -> LiDARSurfaceMesh {
        LiDARSurfaceMesh(vertices: [
            SIMD3(-0.5, -0.5, -2), SIMD3(0.5, -0.5, -2), SIMD3(0, 0.5, -1.95),
            SIMD3(-0.5, -0.5, -4), SIMD3(0.5, -0.5, -4), SIMD3(0, 0.5, -4),
        ],
                         indices: [0, 1, 2, 3, 4, 5])
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("3dseen-surface-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func texture(in directory: URL) throws -> URL {
        var pixels: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 0, 255]
        let context = try XCTUnwrap(CGContext(data: &pixels, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let url = directory.appendingPathComponent("frame_0000.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
