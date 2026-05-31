import XCTest
import CoreGraphics
@testable import ThreeDSeen

final class PBRMaterialTests: XCTestCase {

    private func makeImage(_ w: Int, _ h: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 0.55, green: 0.42, blue: 0.30, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    func testEstimatesMapsOfMatchingSize() async throws {
        let base = makeImage(32, 32)
        let maps = try await AIPBRMaterialEstimator().estimateMaterials(from: base)
        XCTAssertEqual(maps.roughness.width, 32)
        XCTAssertEqual(maps.roughness.height, 32)
        XCTAssertEqual(maps.metallic.width, 32)
        XCTAssertEqual(maps.normal.width, 32)
    }

    func testMaterialPresetsProduceMaterials() {
        for preset in MaterialOverrideLibrary.MaterialPreset.allCases {
            _ = MaterialOverrideLibrary.material(for: preset)
        }
        // No crash + all five presets enumerated.
        XCTAssertEqual(MaterialOverrideLibrary.MaterialPreset.allCases.count, 5)
    }
}
