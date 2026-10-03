import XCTest
#if os(macOS)
@testable import ThreeDSeenMac
#else
@testable import ThreeDSeen
#endif

final class CompactSplatFileTests: XCTestCase {
    func testLittleEndianRecordPreservesGeometryColorOpacityAndQuaternionOrder() throws {
        let file = try CompactSplatFile(data: record())
        let point = try file.point(at: 0)
        XCTAssertEqual(file.count, 1)
        XCTAssertEqual(point.position, SIMD3(1.25, -2.5, 3.75))
        XCTAssertEqual(point.scale, SIMD3(0.25, 0.5, 1))
        XCTAssertEqual(point.rgba, SIMD4<UInt8>(16, 128, 240, 64))
        XCTAssertEqual(point.rotation, SIMD4(1, 0, 0, 0))
        XCTAssertEqual(exp(point.logScale.x), point.scale.x, accuracy: 0.000001)
        XCTAssertEqual(1 / (1 + exp(-point.opacityLogit)), 64 / 255, accuracy: 0.000001)
    }

    func testRejectsEmptyIncompleteAndOutOfRangeReads() throws {
        XCTAssertThrowsError(try CompactSplatFile(data: Data()))
        XCTAssertThrowsError(try CompactSplatFile(data: record().dropLast()))
        let file = try CompactSplatFile(data: record())
        XCTAssertThrowsError(try file.point(at: -1))
        XCTAssertThrowsError(try file.point(at: 1))
    }

    func testRejectsPointCloudOverDevicePreviewLimitBeforeParsingRecords() {
        let data = Data(repeating: 0, count: CompactSplatFile.maximumFileByteCount + 32)
        XCTAssertThrowsError(try CompactSplatFile(data: data)) { error in
            XCTAssertEqual(error as? CompactSplatFile.ReadError, .tooManyPoints)
        }
    }

    func testValidatesEveryRecordAndRejectsInvalidScalesAndRotations() {
        for values in [[Float.nan, -2.5, 3.75, 0.25, 0.5, 1],
                       [1.25, -2.5, 3.75, 0, 0.5, 1],
                       [1.25, -2.5, 3.75, -0.25, 0.5, 1],
                       [1.25, -2.5, 3.75, 0.25, Float.infinity, 1]] {
            XCTAssertThrowsError(try CompactSplatFile(data: record() + record(values: values)))
        }
        XCTAssertThrowsError(try CompactSplatFile(data: record(rotation: [128, 128, 128, 128])))
    }

    func testOpacityEndpointsAndNonIdentityQuaternionRemainUsable() throws {
        for alpha: UInt8 in [0, 255] {
            let point = try CompactSplatFile(data: record(alpha: alpha, rotation: [128, 255, 128, 128])).point(at: 0)
            XCTAssertTrue(point.opacityLogit.isFinite)
            XCTAssertEqual(1 / (1 + exp(-point.opacityLogit)), Float(alpha) / 255, accuracy: 0.000001)
            XCTAssertEqual(point.rotation, SIMD4(0, 1, 0, 0))
        }
    }

    private func record(values: [Float] = [1.25, -2.5, 3.75, 0.25, 0.5, 1],
                        alpha: UInt8 = 64, rotation: [UInt8] = [255, 128, 128, 128]) -> Data {
        var data = Data()
        for value in values {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: [16, 128, 240, alpha] + rotation)
        return data
    }
}
