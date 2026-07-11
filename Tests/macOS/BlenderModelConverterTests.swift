import XCTest
@testable import ThreeDSeenMac

final class BlenderModelConverterTests: XCTestCase {
    func testCommandPassesSourceOutputAndRequestedFormatToBlender() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blender-command-\(UUID().uuidString)", isDirectory: true)
        let runtime = BlenderModelConverter.Runtime(blenderURL: root.appendingPathComponent("blender"))
        let job = BlenderModelConverter.Job(
            sourceURL: root.appendingPathComponent("model.usdz"),
            outputURL: root.appendingPathComponent("model.glb"),
            format: .glb
        )

        let command = BlenderModelConverter(runtime: runtime).command(for: job, scriptURL: root.appendingPathComponent("convert.py"))

        XCTAssertEqual(command.executableURL, runtime.blenderURL)
        XCTAssertEqual(command.arguments, [
            "--background", "--python", root.appendingPathComponent("convert.py").path, "--",
            "--input", job.sourceURL.path, "--output", job.outputURL.path, "--format", "glb"
        ])
    }

    func testValidationRecognizesGLBAndFBXHeaders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blender-output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let glb = root.appendingPathComponent("model.glb")
        var glbData = Data([0x67, 0x6C, 0x54, 0x46])
        appendLittleEndian(2, to: &glbData)
        appendLittleEndian(24, to: &glbData)
        appendLittleEndian(4, to: &glbData)
        glbData.append(contentsOf: [0x4A, 0x53, 0x4F, 0x4E])
        glbData.append(Data("{}  ".utf8))
        try glbData.write(to: glb)
        XCTAssertTrue(BlenderModelConverter.isValidOutput(at: glb, for: .glb))

        let fbx = root.appendingPathComponent("model.fbx")
        var fbxData = Data("Kaydara FBX Binary  \0\u{1A}\0".utf8)
        appendLittleEndian(7_400, to: &fbxData)
        fbxData.append(contentsOf: repeatElement(UInt8(0), count: 40))
        fbxData.append(contentsOf: [0xFA, 0xBC, 0xAB, 0x09, 0xD0, 0xC8, 0xD4, 0x66,
                                    0xB1, 0x76, 0xFB, 0x83, 0x1C, 0xF7, 0x26, 0x7E])
        try fbxData.write(to: fbx)
        XCTAssertTrue(BlenderModelConverter.isValidOutput(at: fbx, for: .fbx))
        XCTAssertFalse(BlenderModelConverter.isValidOutput(at: fbx, for: .glb))

        try Data([0x67, 0x6C, 0x54, 0x46]).write(to: glb)
        XCTAssertFalse(BlenderModelConverter.isValidOutput(at: glb, for: .glb))
        var wrongLength = glbData
        wrongLength.replaceSubrange(8..<12, with: [0, 0, 0, 0])
        try wrongLength.write(to: glb)
        XCTAssertFalse(BlenderModelConverter.isValidOutput(at: glb, for: .glb))
        var oversizedChunk = glbData
        oversizedChunk.replaceSubrange(12..<16, with: [0xFF, 0, 0, 0])
        try oversizedChunk.write(to: glb)
        XCTAssertFalse(BlenderModelConverter.isValidOutput(at: glb, for: .glb))

        var invalidFBXVersion = fbxData
        let versionOffset = Data("Kaydara FBX Binary  \0\u{1A}\0".utf8).count
        invalidFBXVersion.replaceSubrange(versionOffset..<(versionOffset + 4), with: [1, 0, 0, 0])
        try invalidFBXVersion.write(to: fbx)
        XCTAssertFalse(BlenderModelConverter.isValidOutput(at: fbx, for: .fbx))
        try Data(fbxData.dropLast(16)).write(to: fbx)
        XCTAssertFalse(BlenderModelConverter.isValidOutput(at: fbx, for: .fbx))
    }

    func testFailedConversionPreservesExistingExport() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("blender-failure-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let blender = root.appendingPathComponent("blender")
        try Data("#!/bin/sh\nexit 7\n".utf8).write(to: blender)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: blender.path)
        let source = root.appendingPathComponent("source.usda")
        try Data("#usda 1.0".utf8).write(to: source)
        let output = root.appendingPathComponent("existing.glb")
        let existing = Data("glTF-existing".utf8)
        try existing.write(to: output)
        let converter = BlenderModelConverter(runtime: .init(blenderURL: blender))

        XCTAssertThrowsError(try converter.convert(sourceURL: source, to: .glb, outputURL: output))
        XCTAssertEqual(try Data(contentsOf: output), existing)
    }

    private func appendLittleEndian(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    func testInstalledBlenderConvertsARealUSDZToGLBAndFBX() throws {
        let converter = BlenderModelConverter()
        guard converter.isAvailable else { throw XCTSkip("Blender is not installed on this Mac.") }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blender-integration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source.usda")
        try Data("""
        #usda 1.0
        (
            defaultPrim = "Triangle"
        )
        def Mesh "Triangle"
        {
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1, 2]
            point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
        }
        """.utf8).write(to: source)

        for format in [ExportFormat.glb, .fbx] {
            let output = root.appendingPathComponent("model").appendingPathExtension(format.fileExtension)
            let converted = try converter.convert(sourceURL: source, to: format, outputURL: output)
            XCTAssertEqual(converted, output)
            XCTAssertTrue(BlenderModelConverter.isValidOutput(at: output, for: format))
        }
    }
}
