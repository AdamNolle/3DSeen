import XCTest
import SplatIO
@testable import ThreeDSeen

/// Decisive proof that the on-device-generated PLY loads in MetalSplatter's actual reader
/// (the same path the in-app renderer uses). Reading is synchronous in SplatIO.
final class SplatRoundTripTests: XCTestCase, SplatSceneReaderDelegate {
    private var pointCount = 0
    private var finished = false
    private var failure: Error?

    func didStartReading(withPointCount pointCount: UInt32) {}
    func didRead(points: [SplatScenePoint]) { pointCount += points.count }
    func didFinishReading() { finished = true }
    func didFailReading(withError error: Error?) { failure = error }

    func testGeneratedPLYLoadsInMetalSplatterReader() throws {
        let url = try GaussianSplatGenerator.writeDemoPLY(named: "roundtrip-\(UUID())")
        defer { try? FileManager.default.removeItem(at: url) }

        SplatPLYSceneReader(url).read(to: self)

        XCTAssertNil(failure, "reader rejected the generated PLY: \(String(describing: failure))")
        XCTAssertTrue(finished, "reader did not finish")
        XCTAssertEqual(pointCount, 6000, "all generated splats should parse")
    }

    func testGeneratedSplatsFromPointsLoad() throws {
        let pts: [(position: SIMD3<Float>, color: SIMD3<Float>)] =
            (0..<500).map { _ in (.init(.random(in: -1...1), .random(in: -1...1), .random(in: -1...1)),
                                  .init(.random(in: 0...1), .random(in: 0...1), .random(in: 0...1))) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pts-\(UUID()).ply")
        defer { try? FileManager.default.removeItem(at: url) }
        try SplatPLYWriter.write(GaussianSplatGenerator.splats(fromPoints: pts), to: url)

        pointCount = 0; finished = false; failure = nil
        SplatPLYSceneReader(url).read(to: self)
        XCTAssertNil(failure)
        XCTAssertEqual(pointCount, 500)
    }
}
