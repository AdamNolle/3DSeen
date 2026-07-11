import Foundation

/// macOS-only USDZ converter backed by a locally installed Blender. It is intentionally opt-in:
/// iOS keeps its native ModelIO-only export list, and this service validates the file Blender wrote.
public struct BlenderModelConverter: Sendable {
    public struct Runtime: Equatable, Sendable {
        public let blenderURL: URL

        public init(blenderURL: URL) {
            self.blenderURL = blenderURL
        }

        public static func discover(fileManager: FileManager = .default) -> Runtime? {
            let candidates = [
                URL(fileURLWithPath: "/Applications/Blender.app/Contents/MacOS/Blender"),
                URL(fileURLWithPath: "/opt/homebrew/bin/blender"),
                URL(fileURLWithPath: "/usr/local/bin/blender")
            ]
            guard let executable = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
                return nil
            }
            return Runtime(blenderURL: executable)
        }
    }

    public struct Job: Equatable, Sendable {
        public let sourceURL: URL
        public let outputURL: URL
        public let format: ExportFormat

        public init(sourceURL: URL, outputURL: URL, format: ExportFormat) {
            self.sourceURL = sourceURL
            self.outputURL = outputURL
            self.format = format
        }
    }

    public struct Command: Equatable, Sendable {
        public let executableURL: URL
        public let arguments: [String]

        public init(executableURL: URL, arguments: [String]) {
            self.executableURL = executableURL
            self.arguments = arguments
        }
    }

    public enum ConverterError: LocalizedError {
        case unavailable
        case unsupportedFormat(ExportFormat)
        case unsupportedSource(URL)
        case sourceMissing(URL)
        case processFailed(String)
        case invalidOutput(URL)

        public var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Blender is not available for GLB or FBX conversion on this Mac."
            case .unsupportedFormat(let format):
                return "Blender conversion does not support \(format.rawValue)."
            case .unsupportedSource(let url):
                return "Blender conversion requires a USD or USDZ source, not \(url.pathExtension.uppercased())."
            case .sourceMissing(let url):
                return "The source model \(url.lastPathComponent) is no longer available."
            case .processFailed(let detail):
                return "Blender conversion failed. \(detail)"
            case .invalidOutput(let url):
                return "Blender finished without writing a valid \(url.pathExtension.uppercased()) file."
            }
        }
    }

    public let runtime: Runtime?

    public init(runtime: Runtime? = Runtime.discover()) {
        self.runtime = runtime
    }

    public var isAvailable: Bool { runtime != nil }

    public func supports(_ format: ExportFormat) -> Bool {
        format == .glb || format == .fbx
    }

    public func command(for job: Job, scriptURL: URL) -> Command {
        Command(
            executableURL: runtime?.blenderURL ?? URL(fileURLWithPath: "/usr/bin/false"),
            arguments: [
                "--background", "--python", scriptURL.path, "--",
                "--input", job.sourceURL.path, "--output", job.outputURL.path,
                "--format", job.format.fileExtension
            ]
        )
    }

    @discardableResult
    public func convert(sourceURL: URL, to format: ExportFormat, outputURL: URL) throws -> URL {
        guard let runtime else { throw ConverterError.unavailable }
        guard supports(format) else { throw ConverterError.unsupportedFormat(format) }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ConverterError.sourceMissing(sourceURL)
        }
        let usdExtensions = Set(["usd", "usda", "usdc", "usdz"])
        guard usdExtensions.contains(sourceURL.pathExtension.lowercased()) else {
            throw ConverterError.unsupportedSource(sourceURL)
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sourceURL.standardizedFileURL != outputURL.standardizedFileURL else {
            throw ConverterError.invalidOutput(outputURL)
        }
        let stagingURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".pending-\(UUID().uuidString)")
            .appendingPathExtension(outputURL.pathExtension)
        defer { try? fileManager.removeItem(at: stagingURL) }

        let scriptURL = fileManager.temporaryDirectory
            .appendingPathComponent("3dseen-blender-\(UUID().uuidString).py")
        try Self.pythonScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let command = Command(
            executableURL: runtime.blenderURL,
            arguments: self.command(
                for: Job(sourceURL: sourceURL, outputURL: stagingURL, format: format),
                scriptURL: scriptURL
            ).arguments
        )
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            throw ConverterError.processFailed(error.localizedDescription)
        }
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: output, encoding: .utf8) ?? "Blender exited with status \(process.terminationStatus)."
            throw ConverterError.processFailed(String(detail.suffix(900)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard Self.isValidOutput(at: stagingURL, for: format) else {
            throw ConverterError.invalidOutput(stagingURL)
        }
        if fileManager.fileExists(atPath: outputURL.path) {
            _ = try fileManager.replaceItemAt(outputURL, withItemAt: stagingURL)
        } else {
            try fileManager.moveItem(at: stagingURL, to: outputURL)
        }
        return outputURL
    }

    public static func isValidOutput(at url: URL, for format: ExportFormat) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        switch format {
        case .glb:
            guard data.count >= 20,
                  data.starts(with: Data([0x67, 0x6C, 0x54, 0x46])),
                  littleEndianUInt32(data, at: 4) == 2,
                  littleEndianUInt32(data, at: 8) == UInt32(data.count) else { return false }
            let chunkLength = Int(littleEndianUInt32(data, at: 12))
            let jsonChunk = Data([0x4A, 0x53, 0x4F, 0x4E])
            return data[16..<20].elementsEqual(jsonChunk) && chunkLength > 0 && 20 + chunkLength <= data.count
        case .fbx:
            let header = Data("Kaydara FBX Binary  \0\u{1A}\0".utf8)
            let footer = Data([0xFA, 0xBC, 0xAB, 0x09, 0xD0, 0xC8, 0xD4, 0x66,
                               0xB1, 0x76, 0xFB, 0x83, 0x1C, 0xF7, 0x26, 0x7E])
            guard data.count >= 64, data.starts(with: header),
                  littleEndianUInt32(data, at: header.count) >= 7_000 else { return false }
            return Data(data.suffix(256)).range(of: footer) != nil
        default:
            return false
        }
    }

    private static func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static let pythonScript = """
    import argparse
    import bpy
    import os
    import sys

    arguments = sys.argv[sys.argv.index("--") + 1:]
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--format", choices=["glb", "fbx"], required=True)
    options = parser.parse_args(arguments)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.usd_import(filepath=options.input)
    if options.format == "glb":
        bpy.ops.export_scene.gltf(filepath=options.output, export_format="GLB")
    else:
        bpy.ops.export_scene.fbx(filepath=options.output, path_mode='COPY', embed_textures=True)

    if not os.path.isfile(options.output) or os.path.getsize(options.output) == 0:
        raise RuntimeError("Blender did not write the requested output file")
    """
}
