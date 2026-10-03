import XCTest
@testable import ThreeDSeen

final class HandoffResourceCipherTests: XCTestCase {
    func testChunkedResourceRoundTripsWithoutExposingPlaintext() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("handoff-resource-cipher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("capture.zip")
        let encrypted = directory.appendingPathComponent("capture.sealed")
        let decrypted = directory.appendingPathComponent("capture-restored.zip")
        let contents = Data((0..<(1_048_576 + 173)).map { UInt8($0 % 251) })
        let secret = Data(repeating: 0x73, count: 32)
        try contents.write(to: source)

        try HandoffResourceCipher.encrypt(source, to: encrypted, secret: secret)
        XCTAssertNotEqual(try Data(contentsOf: encrypted), contents)
        try HandoffResourceCipher.decrypt(encrypted, to: decrypted, secret: secret)
        XCTAssertEqual(try Data(contentsOf: decrypted), contents)
    }

    func testWrongKeyAndTruncatedResourceAreRejectedAndCleanedUp() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("handoff-resource-cipher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("capture.zip")
        let encrypted = directory.appendingPathComponent("capture.sealed")
        let tampered = directory.appendingPathComponent("capture-truncated.sealed")
        let output = directory.appendingPathComponent("capture-restored.zip")
        try Data(repeating: 0x29, count: 1_048_913).write(to: source)
        let secret = Data(repeating: 0x29, count: 32)
        try HandoffResourceCipher.encrypt(source, to: encrypted, secret: secret)

        XCTAssertThrowsError(try HandoffResourceCipher.decrypt(
            encrypted,
            to: output,
            secret: Data(repeating: 0x28, count: 32)
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))

        var bytes = try Data(contentsOf: encrypted)
        bytes.removeLast()
        try bytes.write(to: tampered)
        XCTAssertThrowsError(try HandoffResourceCipher.decrypt(tampered, to: output, secret: secret))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testEmptyResourceRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("handoff-resource-cipher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("empty.zip")
        let encrypted = directory.appendingPathComponent("empty.sealed")
        let decrypted = directory.appendingPathComponent("empty-restored.zip")
        try Data().write(to: source)
        let secret = Data(repeating: 0x19, count: 32)

        try HandoffResourceCipher.encrypt(source, to: encrypted, secret: secret)
        try HandoffResourceCipher.decrypt(encrypted, to: decrypted, secret: secret)
        XCTAssertEqual(try Data(contentsOf: decrypted), Data())
    }
}
