import XCTest
#if os(macOS)
@testable import ThreeDSeenMac
#else
@testable import ThreeDSeen
#endif

final class PLYValidatorTests: XCTestCase {
    private let coordinates = ["x", "y", "z"]
    private let gaussianProperties = [
        "x", "y", "z", "f_dc_0", "f_dc_1", "f_dc_2", "opacity",
        "scale_0", "scale_1", "scale_2", "rot_0", "rot_1", "rot_2", "rot_3",
    ]

    func testDuplicatePropertiesAndVertexElementsAreRejected() throws {
        XCTAssertFalse(try validate(header(properties: coordinates + ["x"]) + "0 0 0 0\n"))
        let repeated = header(properties: coordinates).replacingOccurrences(
            of: "end_header", with: "element vertex 1\nproperty float extra\nend_header"
        )
        XCTAssertFalse(try validate(repeated + "0 0 0 0\n"))
    }

    func testOversizedBinaryVertexCountIsRejectedWithoutOverflow() throws {
        XCTAssertFalse(try validate(header(
            properties: coordinates, count: Int.max, format: "binary_little_endian"
        )))
    }

    func testViewerImportRejectsPLYHeaderOverPointBudget() throws {
        XCTAssertFalse(try validateImportLimits(Data(header(
            properties: coordinates,
            count: PLYValidator.maximumVertexCount + 1,
            format: "binary_little_endian"
        ).utf8)))
    }

    func testNonFiniteVertexOutsideFormerSampleIsRejected() throws {
        var rows = Array(repeating: "0 0 0", count: 1_025)
        rows[100] = "nan 0 0"
        XCTAssertFalse(try validate(header(properties: coordinates, count: rows.count) + rows.joined(separator: "\n")))
        rows[100] = "0 0 0"
        XCTAssertTrue(try validate(header(properties: coordinates, count: rows.count) + rows.joined(separator: "\n")))
    }

    func testMissingASCIIPropertyAndNonFiniteExtraFieldAreRejected() throws {
        XCTAssertFalse(try validate(header(properties: coordinates + ["nx"]) + "0 0 0\n"))
        XCTAssertFalse(try validate(header(properties: coordinates + ["nx"]) + "0 0 0 inf\n"))
        XCTAssertTrue(try validate(header(properties: coordinates + ["nx"]) + "0 0 0 1\n"))
    }

    func testTrainedSplatRequiresFloatPropertiesAndCompleteFinitePayload() throws {
        let prefix = header(properties: gaussianProperties, count: 1_025, format: "binary_little_endian")
        var data = Data(prefix.utf8)
        data.append(Data(repeating: 0, count: 1_025 * gaussianProperties.count * 4))
        XCTAssertTrue(try validate(data, kind: .trainedSplat))
        let offset = prefix.utf8.count + 100 * gaussianProperties.count * 4
        data.replaceSubrange(offset..<(offset + 4), with: [0, 0, 128, 127])
        XCTAssertFalse(try validate(data, kind: .trainedSplat))
        let integerHeader = header(properties: gaussianProperties, format: "binary_little_endian")
            .replacingOccurrences(of: "property float", with: "property int")
        var integers = Data(integerHeader.utf8)
        integers.append(Data(repeating: 0, count: gaussianProperties.count * 4))
        XCTAssertFalse(try validate(integers, kind: .trainedSplat))
    }

    func testUnsupportedVersionAndVerticesAfterOtherElementsAreRejected() throws {
        XCTAssertFalse(try validate(header(properties: coordinates).replacingOccurrences(of: "1.0", with: "2.0") + "0 0 0"))
        let reordered = header(properties: coordinates).replacingOccurrences(
            of: "element vertex", with: "element face 1\nproperty list uchar int vertex_indices\nelement vertex"
        )
        XCTAssertFalse(try validate(reordered + "0 0 0"))
        XCTAssertTrue(try validate(header(properties: coordinates).replacingOccurrences(of: "\n", with: "\r\n") + "0 0 0\r\n"))
    }

    private func header(properties: [String], count: Int = 1, format: String = "ascii") -> String {
        "ply\nformat \(format) 1.0\nelement vertex \(count)\n"
            + properties.map { "property float \($0)\n" }.joined() + "end_header\n"
    }

    private func validate(_ text: String) throws -> Bool {
        try validate(Data(text.utf8))
    }

    private func validate(_ data: Data, kind: PLYPayloadKind = .geometry) throws -> Bool {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ply-validation-\(UUID()).ply")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        return PLYValidator.isValid(url, kind: kind)
    }

    private func validateImportLimits(_ data: Data) throws -> Bool {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ply-import-limit-\(UUID()).ply")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        return PLYValidator.isWithinImportLimits(url)
    }
}
