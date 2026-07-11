import Combine
import Foundation
import Darwin

/// Installs the optional, local-only trained-splat runtime used by `NerfstudioSplatTrainer`.
/// The service is confined to direct-distribution macOS builds because it invokes user-visible
/// package tools and writes the runtime beneath Application Support.
@MainActor
public final class NerfstudioRuntimeInstaller: ObservableObject {
    public enum Stage: Equatable {
        case idle
        case installingCOLMAP
        case creatingEnvironment
        case installingPackages
        case completed
        case failed(String)

        public var label: String {
            switch self {
            case .idle: return "Not configured"
            case .installingCOLMAP: return "Installing COLMAP"
            case .creatingEnvironment: return "Creating Python environment"
            case .installingPackages: return "Installing Nerfstudio"
            case .completed: return "Ready"
            case .failed(let message): return message
            }
        }
    }

    public struct Paths: Equatable {
        public let brewURL: URL
        public let pythonURL: URL
        public let colmapURL: URL
        public let virtualEnvironmentURL: URL

        public init(brewURL: URL, pythonURL: URL, colmapURL: URL, virtualEnvironmentURL: URL) {
            self.brewURL = brewURL
            self.pythonURL = pythonURL
            self.colmapURL = colmapURL
            self.virtualEnvironmentURL = virtualEnvironmentURL
        }

        public static func discover(fileManager: FileManager = .default) -> Paths? {
            let brewCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
                .map(URL.init(fileURLWithPath:))
            let pythonCandidates = ["/opt/homebrew/bin/python3.11", "/usr/local/bin/python3.11", "/usr/bin/python3"]
                .map(URL.init(fileURLWithPath:))
            guard let brew = brewCandidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }),
                  let python = pythonCandidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
                return nil
            }
            let colmapCandidates = ["/opt/homebrew/bin/colmap", "/usr/local/bin/colmap", "/usr/bin/colmap"]
                .map(URL.init(fileURLWithPath:))
            let colmap = colmapCandidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) })
                ?? URL(fileURLWithPath: "/opt/homebrew/bin/colmap")
            let venv = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/3DSeen/trainer/venv", isDirectory: true)
            return Paths(brewURL: brew, pythonURL: python, colmapURL: colmap, virtualEnvironmentURL: venv)
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

    public enum InstallerError: LocalizedError {
        case unavailable
        case commandFailed(String)

        public var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Homebrew and Python 3.11 are required to install the trained-splat runtime."
            case .commandFailed(let output):
                return "Runtime setup failed. \(output)"
            }
        }
    }

    @Published public private(set) var stage: Stage = .idle
    @Published public private(set) var recentOutput = ""
    @Published public private(set) var isInstalling = false

    public let paths: Paths?
    private let colmapInstalled: Bool
    private let runtimeVerifier: () -> Bool
    private var activeProcess: Process?
    private var cancellationRequested = false

    public init(paths: Paths? = Paths.discover(), colmapInstalled: Bool? = nil,
                runtimeVerifier: @escaping () -> Bool = { NerfstudioSplatTrainer.Runtime.discover() != nil }) {
        self.paths = paths
        self.colmapInstalled = colmapInstalled ?? paths.map { FileManager.default.isExecutableFile(atPath: $0.colmapURL.path) } ?? false
        self.runtimeVerifier = runtimeVerifier
        if runtimeVerifier() {
            stage = .completed
        }
    }

    public var canInstall: Bool { paths != nil && !isInstalling }

    public func commands() -> [Command] {
        guard let paths else { return [] }
        let pip = paths.virtualEnvironmentURL.appendingPathComponent("bin/pip")
        var commands: [Command] = []
        if !colmapInstalled {
            commands.append(Command(executableURL: paths.brewURL, arguments: ["install", "colmap"]))
        }
        commands.append(Command(executableURL: paths.pythonURL, arguments: ["-m", "venv", paths.virtualEnvironmentURL.path]))
        commands.append(Command(executableURL: pip, arguments: ["install", "--upgrade", "pip"]))
        commands.append(Command(executableURL: pip, arguments: ["install", "nerfstudio==1.1.5", "pymeshlab"]))
        return commands
    }

    public func install() async throws {
        guard paths != nil else { throw InstallerError.unavailable }
        isInstalling = true
        cancellationRequested = false
        recentOutput = ""
        defer {
            isInstalling = false
            activeProcess = nil
        }

        let installCommands = commands()
        for (index, command) in installCommands.enumerated() {
            stage = stage(for: index, commandCount: installCommands.count)
            try await execute(command)
        }
        guard runtimeVerifier() else {
            stage = .failed("Runtime was not detected after setup")
            throw InstallerError.commandFailed("Nerfstudio commands were not found after installation.")
        }
        stage = .completed
    }

    public func cancel() {
        cancellationRequested = true
        if let activeProcess { Self.terminateProcessGroup(activeProcess) }
        stage = .idle
        isInstalling = false
    }

    private func stage(for index: Int, commandCount: Int) -> Stage {
        guard !colmapInstalled, commandCount == 4 else {
            return index == 0 ? .creatingEnvironment : .installingPackages
        }
        switch index {
        case 0: return .installingCOLMAP
        case 1: return .creatingEnvironment
        default: return .installingPackages
        }
    }

    private func execute(_ command: Command) async throws {
        let process = Process()
        let outputPipe = Pipe()
        Self.configureIsolatedProcess(process, command: command)
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        activeProcess = process
        do {
            try process.run()
        } catch {
            stage = .failed("Could not run \(command.executableURL.lastPathComponent)")
            throw InstallerError.commandFailed(error.localizedDescription)
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
            throw InstallerError.commandFailed(String(text.suffix(900)).trimmingCharacters(in: .whitespacesAndNewlines))
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
}
