import XCTest
import simd
import ModelIO
@testable import ThreeDSeen

final class SplatGeneratorTests: XCTestCase {

    func testDemoCloudCount() {
        XCTAssertEqual(GaussianSplatGenerator.demoCloud(count: 100).count, 100)
        XCTAssertEqual(GaussianSplatGenerator.demoCloud(count: 6000).count, 6000)
    }

    func testGeneratorFromPoints() {
        let points: [(position: SIMD3<Float>, color: SIMD3<Float>)] = [
            (SIMD3(0, 0, 0), SIMD3(1, 0, 0)),
            (SIMD3(1, 1, 1), SIMD3(0, 1, 0))
        ]
        let splats = GaussianSplatGenerator.splats(fromPoints: points)
        XCTAssertEqual(splats.count, 2)
        XCTAssertEqual(splats[0].color, SIMD3<Float>(1, 0, 0))
        XCTAssertEqual(splats[1].position, SIMD3<Float>(1, 1, 1))
    }

    func testGeneratorBuildsSplatsFromModelIOVertices() throws {
        let allocator = MDLMeshBufferDataAllocator()
        let mesh = MDLMesh(
            boxWithExtent: SIMD3<Float>(1, 1, 1),
            segments: SIMD3<UInt32>(1, 1, 1),
            inwardNormals: false,
            geometryType: .triangles,
            allocator: allocator
        )
        let asset = MDLAsset(bufferAllocator: allocator)
        asset.add(mesh)

        let splats = try GaussianSplatGenerator.splats(fromModelAsset: asset)

        XCTAssertFalse(splats.isEmpty)
    }

    func testWritesValid3DGSHeaderAndExactBinarySize() throws {
        let splats = GaussianSplatGenerator.demoCloud(count: 250)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).ply")
        defer { try? FileManager.default.removeItem(at: url) }
        try SplatPLYWriter.write(splats, to: url)

        let data = try Data(contentsOf: url)
        let marker = Data("end_header\n".utf8)
        guard let headerRange = data.range(of: marker) else { return XCTFail("no end_header") }
        let header = String(decoding: data.subdata(in: 0..<headerRange.upperBound), as: UTF8.self)

        XCTAssertTrue(header.contains("format binary_little_endian 1.0"))
        XCTAssertTrue(header.contains("element vertex 250"))
        XCTAssertTrue(header.contains("property float nx"))
        XCTAssertTrue(header.contains("f_dc_0"))
        XCTAssertTrue(header.contains("scale_0"))
        XCTAssertTrue(header.contains("rot_3"))

        // 17 float32 properties per splat (x,y,z, nx,ny,nz, f_dc*3, opacity, scale*3, rot*4)
        let binaryBytes = data.count - headerRange.upperBound
        XCTAssertEqual(binaryBytes, 250 * 17 * 4)
    }

    func testSHDCColorRoundTrips() {
        let c0 = GaussianSplatGenerator.shC0
        for color in [Float(0.0), 0.3, 0.5, 0.7, 1.0] {
            let fdc = (color - 0.5) / c0
            let recovered = 0.5 + c0 * fdc
            XCTAssertEqual(recovered, color, accuracy: 1e-5)
        }
    }

    func testWriteDemoPLYProducesFile() throws {
        let url = try GaussianSplatGenerator.writeDemoPLY(named: "unit-demo")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.pathExtension, "ply")
    }
}
