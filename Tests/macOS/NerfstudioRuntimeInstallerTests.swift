import XCTest
import Darwin
@testable import ThreeDSeenMac

@MainActor
final class NerfstudioRuntimeInstallerTests: XCTestCase {
    func testInstallerBuildsPinnedRuntimeCommandsWhenColmapIsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-install-\(UUID().uuidString)", isDirectory: true)
        let paths = NerfstudioRuntimeInstaller.Paths(
            brewURL: root.appendingPathComponent("brew"),
            pythonURL: root.appendingPathComponent("python3.11"),
            colmapURL: root.appendingPathComponent("colmap"),
            virtualEnvironmentURL: root.appendingPathComponent("venv", isDirectory: true)
        )

        let commands = NerfstudioRuntimeInstaller(paths: paths, colmapInstalled: false).commands()

        XCTAssertEqual(commands.count, 4)
        XCTAssertEqual(commands[0].executableURL, paths.brewURL)
        XCTAssertEqual(commands[0].arguments, ["install", "colmap"])
        XCTAssertEqual(commands[1].executableURL, paths.pythonURL)
        XCTAssertEqual(commands[1].arguments, ["-m", "venv", paths.virtualEnvironmentURL.path])
        XCTAssertEqual(commands[3].arguments, ["install", "nerfstudio==1.1.5", "pymeshlab"])
    }

    func testInstallerSkipsColmapInstallWhenItAlreadyExists() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-install-\(UUID().uuidString)", isDirectory: true)
        let paths = NerfstudioRuntimeInstaller.Paths(
            brewURL: root.appendingPathComponent("brew"),
            pythonURL: root.appendingPathComponent("python3.11"),
            colmapURL: root.appendingPathComponent("colmap"),
            virtualEnvironmentURL: root.appendingPathComponent("venv", isDirectory: true)
        )

        XCTAssertEqual(NerfstudioRuntimeInstaller(paths: paths, colmapInstalled: true).commands().count, 3)
    }

    func testInstallerRunsAllSetupStagesAndRefreshesAvailability() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("runtime-installer-process-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let brew = try command(named: "brew", in: root, script: "#!/bin/sh\nexit 0\n")
        let python = try command(named: "python3.11", in: root, script: """
        #!/bin/sh
        if [ "$1" = "-m" ] && [ "$2" = "venv" ]; then
          mkdir -p "$3/bin"
          printf '#!/bin/sh\\nexit 0\\n' > "$3/bin/pip"
          chmod +x "$3/bin/pip"
        fi
        """)
        let paths = NerfstudioRuntimeInstaller.Paths(
            brewURL: brew,
            pythonURL: python,
            colmapURL: root.appendingPathComponent("colmap"),
            virtualEnvironmentURL: root.appendingPathComponent("venv", isDirectory: true)
        )
        let installer = NerfstudioRuntimeInstaller(
            paths: paths,
            colmapInstalled: false,
            runtimeVerifier: { true }
        )

        try await installer.install()

        XCTAssertEqual(installer.stage, .completed)
        XCTAssertFalse(installer.isInstalling)
    }

    func testInstallerCancellationTerminatesDescendantProcess() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("installer-cancel-\(UUID())", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let childPIDURL = root.appendingPathComponent("child.pid")
        let brew = try command(named: "brew", in: root, script: """
        #!/bin/sh
        sleep 30 &
        echo $! > "\(childPIDURL.path)"
        wait
        """)
        let paths = NerfstudioRuntimeInstaller.Paths(
            brewURL: brew,
            pythonURL: URL(fileURLWithPath: "/usr/bin/true"),
            colmapURL: root.appendingPathComponent("colmap"),
            virtualEnvironmentURL: root.appendingPathComponent("venv", isDirectory: true)
        )
        let installer = NerfstudioRuntimeInstaller(paths: paths, colmapInstalled: false)
        let task = Task { try await installer.install() }
        for _ in 0..<200 where !fm.fileExists(atPath: childPIDURL.path) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard fm.fileExists(atPath: childPIDURL.path) else {
            task.cancel()
            _ = try? await task.value
            return XCTFail("The disposable installer process did not launch within 10 seconds.")
        }
        let childPID = try XCTUnwrap(
            Int32(String(contentsOf: childPIDURL).trimmingCharacters(in: .whitespacesAndNewlines))
        )

        task.cancel()
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertFalse(installer.isInstalling)
            XCTAssertEqual(installer.stage, .idle)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(kill(childPID, 0), -1, "Installer descendant should not survive cancellation")
        XCTAssertEqual(errno, ESRCH)
    }

    private func command(named name: String, in directory: URL, script: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
