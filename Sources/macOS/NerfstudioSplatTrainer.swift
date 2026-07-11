import Foundation
import Combine
import Darwin

/// Local-only Gaussian-splat trainer backed by a user-installed Nerfstudio runtime. This service
/// never fabricates a radiance field: it only returns a PLY after preprocessing, training, and
/// Nerfstudio's own export command all succeed.
@MainActor
public final class NerfstudioSplatTrainer: ObservableObject {
    public enum Stage: Equatable {
        case idle
        case preprocessing
        case training
        case exporting
        case completed
        case failed(String)

        public var label: String {
            switch self {
            case .idle: return "Ready"
            case .preprocessing: return "Preparing images"
            case .training: return "Training splat"
            case .exporting: return "Exporting splat"
            case .completed: return "Trained splat ready"
            case .failed(let message): return message
            }
        }
    }

    public struct Runtime: Equatable {
        public let processDataURL: URL
        public let trainURL: URL
        public let exportURL: URL
        public let colmapURL: URL

        public init(processDataURL: URL, trainURL: URL, exportURL: URL, colmapURL: URL) {
            self.processDataURL = processDataURL
            self.trainURL = trainURL
            self.exportURL = exportURL
            self.colmapURL = colmapURL
        }

        public static func discover(fileManager: FileManager = .default) -> Runtime? {
            let trainerRoot = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/3DSeen/trainer/venv/bin", isDirectory: true)
            let processData = trainerRoot.appendingPathComponent("ns-process-data")
            let train = trainerRoot.appendingPathComponent("ns-train")
            let export = trainerRoot.appendingPathComponent("ns-export")
            let colmapCandidates = [
                URL(fileURLWithPath: "/opt/homebrew/bin/colmap"),
                URL(fileURLWithPath: "/usr/local/bin/colmap"),
                URL(fileURLWithPath: "/usr/bin/colmap")
            ]

            guard [processData, train, export].allSatisfy({ fileManager.isExecutableFile(atPath: $0.path) }),
                  let colmap = colmapCandidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
                return nil
            }
            return Runtime(processDataURL: processData, trainURL: train, exportURL: export, colmapURL: colmap)
        }
    }

    public struct Command: Equatable {
        public let executableURL: URL
        public let arguments: [String]

        public init(executableURL: URL, arguments: [String]) {
            self.executableURL = executableURL
            self.arguments = arguments
        }
    }

    public struct Job: Equatable {
        public let inputImagesURL: URL
        public let workingDirectory: URL
        public let scanID: UUID
        public let iterationCount: Int

        public init(inputImagesURL: URL, workingDirectory: URL, scanID: UUID, iterationCount: Int = 7_000) {
            self.inputImagesURL = inputImagesURL
            self.workingDirectory = workingDirectory
            self.scanID = scanID
            self.iterationCount = iterationCount
        }

        public var processedDataURL: URL {
            workingDirectory.appendingPathComponent("nerfstudio-data", isDirectory: true)
        }

        public var runDirectory: URL {
            workingDirectory.appendingPathComponent("runs", isDirectory: true)
        }

        public var exportDirectory: URL {
            workingDirectory.appendingPathComponent("export", isDirectory: true)
        }

        public var exportURL: URL {
            exportDirectory.appendingPathComponent("trained-splat.ply")
        }

        fileprivate var experimentName: String { "3dseen-\(scanID.uuidString.lowercased())" }
    }

    public enum TrainerError: LocalizedError {
        case unavailable
        case invalidInput(URL)
        case processFailed(command: String, output: String)
        case trainingConfigurationMissing(URL)
        case exportMissing(URL)

        public var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Nerfstudio and COLMAP are not configured on this Mac."
            case .invalidInput(let url):
                return "The handoff does not contain image frames at \(url.lastPathComponent)."
            case .processFailed(let command, let output):
                return "\(command) failed. \(output)"
            case .trainingConfigurationMissing:
                return "Nerfstudio completed without writing a training configuration."
            case .exportMissing:
                return "Nerfstudio completed without writing a trained splat PLY."
            }
        }
    }

    @Published public private(set) var stage: Stage = .idle
    @Published public private(set) var recentOutput: String = ""
    @Published public private(set) var isRunning = false

    @Published public private(set) var runtime: Runtime?
    private let runtimeProvider: () -> Runtime?
    private var activeProcess: Process?
    private var cancellationRequested = false

    public init(runtime: Runtime? = nil, runtimeProvider: @escaping () -> Runtime? = { Runtime.discover() }) {
        self.runtimeProvider = runtimeProvider
        self.runtime = runtime ?? runtimeProvider()
    }

    public var isAvailable: Bool { runtime != nil }

    /// Re-check the configured runtime after the in-app installer completes.
    @discardableResult
    public func refreshRuntime() -> Bool {
        runtime = runtimeProvider()
        return isAvailable
    }

    public func commands(for job: Job) throws -> [Command] {
        guard let runtime else { throw TrainerError.unavailable }
        return [
            Command(
                executableURL: runtime.processDataURL,
                arguments: [
                    "images", "--data", job.inputImagesURL.path,
                    "--output-dir", job.processedDataURL.path,
                    "--colmap-cmd", runtime.colmapURL.path,
                    "--matching-method", "sequential",
                    "--num-downscales", "2"
                ]
            ),
            Command(
                executableURL: runtime.trainURL,
                arguments: [
                    "splatfacto",
                    "--machine.device-type", "mps",
                    "--max-num-iterations", "\(job.iterationCount)",
                    "--output-dir", job.runDirectory.path,
                    "--experiment-name", job.experimentName,
                    "--timestamp", "run",
                    "--vis", "viewer",
                    "nerfstudio-data", "--data", job.processedDataURL.path
                ]
            )
        ]
    }

    @discardableResult
    public func train(job: Job) async throws -> URL {
        guard CaptureArchiveInspector.containsImageFrames(in: job.inputImagesURL) else {
            throw TrainerError.invalidInput(job.inputImagesURL)
        }
        let commands = try commands(for: job)
        let fm = FileManager.default
        try fm.createDirectory(at: job.workingDirectory, withIntermediateDirectories: true)
        for staleDirectory in [job.processedDataURL, job.runDirectory, job.exportDirectory] where
            fm.fileExists(atPath: staleDirectory.path) {
            try fm.removeItem(at: staleDirectory)
        }

        isRunning = true
        cancellationRequested = false
        recentOutput = ""
        defer { isRunning = false; activeProcess = nil }

        stage = .preprocessing
        try await execute(commands[0])

        stage = .training
        try await execute(commands[1])

        guard let configURL = findTrainingConfiguration(in: job.runDirectory) else {
            throw TrainerError.trainingConfigurationMissing(job.runDirectory)
        }

        stage = .exporting
        try fm.createDirectory(at: job.exportDirectory, withIntermediateDirectories: true)
        try await execute(Command(
            executableURL: runtime!.exportURL,
            arguments: [
                "gaussian-splat",
                "--load-config", configURL.path,
                "--output-dir", job.exportDirectory.path,
                "--output-filename", job.exportURL.lastPathComponent
            ]
        ))

        guard Self.isValidTrainedPLY(at: job.exportURL) else {
            throw TrainerError.exportMissing(job.exportURL)
        }
        stage = .completed
        return job.exportURL
    }

    public func cancel() {
        cancellationRequested = true
        if let activeProcess { Self.terminateProcessGroup(activeProcess) }
        stage = .idle
        isRunning = false
    }

    public static func isValidTrainedPLY(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let terminatorRange = data.range(of: Data("end_header\n".utf8))
                ?? data.range(of: Data("end_header\r\n".utf8)) else { return false }
        let payloadOffset = terminatorRange.upperBound
        guard let header = String(data: data[..<payloadOffset], encoding: .ascii) else { return false }
        let lines = header.components(separatedBy: .newlines)
        guard lines.first == "ply",
              lines.contains("format binary_little_endian 1.0") else { return false }

        var vertexCount: Int?
        var vertexStride = 0
        var vertexProperties = Set<String>()
        var propertyOffsets: [String: (offset: Int, size: Int)] = [:]
        var parsingVertex = false
        let scalarSizes = [
            "char": 1, "uchar": 1, "int8": 1, "uint8": 1,
            "short": 2, "ushort": 2, "int16": 2, "uint16": 2,
            "int": 4, "uint": 4, "int32": 4, "uint32": 4, "float": 4, "float32": 4,
            "double": 8, "float64": 8
        ]
        for line in lines {
            let parts = line.split(separator: " ").map(String.init)
            if parts.count == 3, parts[0] == "element" {
                parsingVertex = parts[1] == "vertex"
                if parsingVertex { vertexCount = Int(parts[2]) }
                continue
            }
            guard parsingVertex, parts.count == 3, parts[0] == "property",
                  let size = scalarSizes[parts[1]] else { continue }
            propertyOffsets[parts[2]] = (vertexStride, size)
            vertexStride += size
            vertexProperties.insert(parts[2])
        }

        let requiredProperties: Set<String> = [
            "x", "y", "z", "f_dc_0", "f_dc_1", "f_dc_2",
            "opacity", "scale_0", "scale_1", "scale_2",
            "rot_0", "rot_1", "rot_2", "rot_3"
        ]
        guard let vertexCount, vertexCount > 0, vertexStride > 0,
              requiredProperties.isSubset(of: vertexProperties),
              requiredProperties.allSatisfy({ propertyOffsets[$0]?.size == 4 }),
              data.count >= payloadOffset + vertexCount * vertexStride else { return false }

        let sampledVertices: [Int]
        if vertexCount <= 1_024 {
            sampledVertices = Array(0..<vertexCount)
        } else {
            sampledVertices = [0, vertexCount / 2, vertexCount - 1]
        }
        for vertex in sampledVertices {
            for property in requiredProperties {
                guard let offset = propertyOffsets[property]?.offset else { return false }
                let start = payloadOffset + vertex * vertexStride + offset
                let bits = UInt32(data[start])
                    | UInt32(data[start + 1]) << 8
                    | UInt32(data[start + 2]) << 16
                    | UInt32(data[start + 3]) << 24
                guard Float(bitPattern: bits).isFinite else { return false }
            }
        }
        return true
    }

    private func findTrainingConfiguration(in directory: URL) -> URL? {
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return nil }
        return files.compactMap { $0 as? URL }
            .first { $0.lastPathComponent == "config.yml" }
    }

    private func execute(_ command: Command) async throws {
        let process = Process()
        let outputPipe = Pipe()
        Self.configureIsolatedProcess(process, command: command)
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        activeProcess = process

        let commandDescription = ([command.executableURL.lastPathComponent] + command.arguments).joined(separator: " ")
        do {
            try process.run()
        } catch {
            throw TrainerError.processFailed(command: commandDescription, output: error.localizedDescription)
        }

        let output = await withTaskCancellationHandler {
            await Task.detached(priority: .utility) {
                outputPipe.fileHandleForReading.readDataToEndOfFile()
            }.value
        } onCancel: {
            Self.terminateProcessGroup(process)
        }
        process.waitUntilExit()

        if cancellationRequested || Task.isCancelled {
            stage = .idle
            throw CancellationError()
        }
        let text = String(data: output, encoding: .utf8) ?? ""
        recentOutput = String(text.suffix(4_000))
        guard process.terminationStatus == 0 else {
            stage = .failed("\(command.executableURL.lastPathComponent) failed")
            throw TrainerError.processFailed(command: commandDescription, output: Self.conciseOutput(text))
        }
    }

    private static func configureIsolatedProcess(_ process: Process, command: Command) {
        let launcher = URL(fileURLWithPath: "/usr/bin/python3")
        if FileManager.default.isExecutableFile(atPath: launcher.path) {
            process.executableURL = launcher
            process.arguments = [
                "-c", Self.processGroupLauncher,
                command.executableURL.path
            ] + command.arguments
        } else {
            process.executableURL = command.executableURL
            process.arguments = command.arguments
        }
    }

    private static let processGroupLauncher = """
    import os, sys
    try:
        os.setsid()
    except PermissionError:
        try:
            os.setpgid(0, 0)
        except PermissionError:
            pass
    os.execv(sys.argv[1], sys.argv[1:])
    """

    nonisolated private static func terminateProcessGroup(_ process: Process) {
        let identifier = process.processIdentifier
        guard identifier > 0 else { return }
        if kill(-identifier, SIGTERM) != 0 {
            process.terminate()
        }
    }

    private static func conciseOutput(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.suffix(900))
    }
}
