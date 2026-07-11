import XCTest
import AppKit
import Darwin
@testable import ThreeDSeenMac

@MainActor
final class ComputeStageTests: XCTestCase {

    func testTrainerRuntimeRequiresAllCommands() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("trainer-runtime-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = NerfstudioSplatTrainer.Runtime(
            processDataURL: root.appendingPathComponent("ns-process-data"),
            trainURL: root.appendingPathComponent("ns-train"),
            exportURL: root.appendingPathComponent("ns-export"),
            colmapURL: root.appendingPathComponent("colmap")
        )
        let trainer = NerfstudioSplatTrainer(runtime: runtime)

        XCTAssertTrue(trainer.isAvailable)
        XCTAssertEqual(trainer.runtime, runtime)
    }

    func testTrainerRefreshesRuntimeAfterSetupCompletes() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("trainer-refresh-\(UUID().uuidString)", isDirectory: true)
        let runtime = NerfstudioSplatTrainer.Runtime(
            processDataURL: root.appendingPathComponent("ns-process-data"),
            trainURL: root.appendingPathComponent("ns-train"),
            exportURL: root.appendingPathComponent("ns-export"),
            colmapURL: root.appendingPathComponent("colmap")
        )
        var discovered: NerfstudioSplatTrainer.Runtime?
        let trainer = NerfstudioSplatTrainer(runtime: nil, runtimeProvider: { discovered })

        XCTAssertFalse(trainer.isAvailable)
        discovered = runtime
        XCTAssertTrue(trainer.refreshRuntime())
        XCTAssertEqual(trainer.runtime, runtime)
    }

    func testTrainerBuildsBoundedMPSCommands() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("trainer-commands-\(UUID().uuidString)", isDirectory: true)
        let runtime = NerfstudioSplatTrainer.Runtime(
            processDataURL: root.appendingPathComponent("ns-process-data"),
            trainURL: root.appendingPathComponent("ns-train"),
            exportURL: root.appendingPathComponent("ns-export"),
            colmapURL: root.appendingPathComponent("colmap")
        )
        let job = NerfstudioSplatTrainer.Job(
            inputImagesURL: root.appendingPathComponent("images", isDirectory: true),
            workingDirectory: root.appendingPathComponent("work", isDirectory: true),
            scanID: UUID(uuidString: "12345678-1234-5678-9ABC-123456789ABC")!,
            iterationCount: 7_000
        )

        let commands = try NerfstudioSplatTrainer(runtime: runtime).commands(for: job)

        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands[0].executableURL, runtime.processDataURL)
        XCTAssertEqual(commands[0].arguments, [
            "images", "--data", job.inputImagesURL.path,
            "--output-dir", job.processedDataURL.path,
            "--colmap-cmd", runtime.colmapURL.path,
            "--matching-method", "sequential", "--num-downscales", "2"
        ])
        XCTAssertEqual(commands[1].executableURL, runtime.trainURL)
        XCTAssertTrue(commands[1].arguments.contains("--machine.device-type"))
        XCTAssertTrue(commands[1].arguments.contains("mps"))
        XCTAssertTrue(commands[1].arguments.contains("7000"))
        XCTAssertTrue(commands[1].arguments.contains("nerfstudio-data"))
    }

    func testTrainedPLYValidationRequiresNerfstudioShapeAndPayload() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trained-splat-\(UUID().uuidString).ply")
        defer { try? FileManager.default.removeItem(at: url) }

        try validTrainedPLYData().write(to: url)
        XCTAssertTrue(NerfstudioSplatTrainer.isValidTrainedPLY(at: url))

        try Data(trainedPLYHeader.utf8).write(to: url)
        XCTAssertFalse(NerfstudioSplatTrainer.isValidTrainedPLY(at: url), "A header-only PLY is truncated")

        var nonfinite = validTrainedPLYData()
        nonfinite.replaceSubrange(nonfinite.count - 56..<nonfinite.count - 52, with: [0, 0, 0xC0, 0x7F])
        try nonfinite.write(to: url)
        XCTAssertFalse(NerfstudioSplatTrainer.isValidTrainedPLY(at: url), "NaN geometry must be rejected")
    }

    func testTrainerRunsAllStagesWithValidatedOutput() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("trainer-process-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let imageDirectory = root.appendingPathComponent("images", isDirectory: true)
        try fm.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        try writeTestPNG(to: imageDirectory.appendingPathComponent("frame.png"))

        let processData = try command(named: "process", in: root, script: """
        #!/bin/sh
        exit 0
        """)
        let train = try command(named: "train", in: root, script: """
        #!/bin/sh
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--output-dir" ]; then
            mkdir -p "$2/test"
            printf "config" > "$2/test/config.yml"
            exit 0
          fi
          shift
        done
        exit 1
        """)
        let export = try command(named: "export", in: root, script: """
        #!/bin/sh
        output_dir=""
        file_name=""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--output-dir" ]; then output_dir="$2"; shift 2; continue; fi
          if [ "$1" = "--output-filename" ]; then file_name="$2"; shift 2; continue; fi
          shift
        done
        mkdir -p "$output_dir"
        cat > "$output_dir/$file_name" <<'PLY'
        ply
        format binary_little_endian 1.0
        element vertex 1
        property float x
        property float y
        property float z
        property float f_dc_0
        property float f_dc_1
        property float f_dc_2
        property float opacity
        property float scale_0
        property float scale_1
        property float scale_2
        property float rot_0
        property float rot_1
        property float rot_2
        property float rot_3
        end_header
        PLY
        dd if=/dev/zero bs=56 count=1 >> "$output_dir/$file_name" 2>/dev/null
        """)
        let runtime = NerfstudioSplatTrainer.Runtime(
            processDataURL: processData,
            trainURL: train,
            exportURL: export,
            colmapURL: URL(fileURLWithPath: "/usr/bin/true")
        )
        let trainer = NerfstudioSplatTrainer(runtime: runtime)
        let job = NerfstudioSplatTrainer.Job(
            inputImagesURL: imageDirectory,
            workingDirectory: root.appendingPathComponent("work", isDirectory: true),
            scanID: UUID(),
            iterationCount: 2
        )

        let output = try await trainer.train(job: job)

        XCTAssertEqual(output, job.exportURL)
        XCTAssertEqual(trainer.stage, .completed)
        XCTAssertTrue(NerfstudioSplatTrainer.isValidTrainedPLY(at: output))
    }

    func testTrainerClearsStaleRunArtifactsBeforeRetry() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("trainer-stale-\(UUID())", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let images = root.appendingPathComponent("images", isDirectory: true)
        try fm.createDirectory(at: images, withIntermediateDirectories: true)
        try writeTestPNG(to: images.appendingPathComponent("frame.png"))
        let job = NerfstudioSplatTrainer.Job(
            inputImagesURL: images,
            workingDirectory: root.appendingPathComponent("work", isDirectory: true),
            scanID: UUID()
        )
        try fm.createDirectory(at: job.runDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: job.exportDirectory, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: job.runDirectory.appendingPathComponent("config.yml"))
        try validTrainedPLYData().write(to: job.exportURL)
        let runtime = NerfstudioSplatTrainer.Runtime(
            processDataURL: URL(fileURLWithPath: "/usr/bin/true"),
            trainURL: URL(fileURLWithPath: "/usr/bin/true"),
            exportURL: URL(fileURLWithPath: "/usr/bin/true"),
            colmapURL: URL(fileURLWithPath: "/usr/bin/true")
        )

        do {
            _ = try await NerfstudioSplatTrainer(runtime: runtime).train(job: job)
            XCTFail("A retry must not accept stale config or PLY files")
        } catch let error as NerfstudioSplatTrainer.TrainerError {
            guard case .trainingConfigurationMissing = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(fm.fileExists(atPath: job.exportURL.path))
    }

    func testTrainerSurfacesSubprocessFailure() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("trainer-failure-\(UUID())", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let images = root.appendingPathComponent("images", isDirectory: true)
        try fm.createDirectory(at: images, withIntermediateDirectories: true)
        try writeTestPNG(to: images.appendingPathComponent("frame.png"))
        let runtime = NerfstudioSplatTrainer.Runtime(
            processDataURL: URL(fileURLWithPath: "/usr/bin/false"),
            trainURL: URL(fileURLWithPath: "/usr/bin/true"),
            exportURL: URL(fileURLWithPath: "/usr/bin/true"),
            colmapURL: URL(fileURLWithPath: "/usr/bin/true")
        )
        let trainer = NerfstudioSplatTrainer(runtime: runtime)
        let job = NerfstudioSplatTrainer.Job(
            inputImagesURL: images,
            workingDirectory: root.appendingPathComponent("work", isDirectory: true),
            scanID: UUID()
        )

        do {
            _ = try await trainer.train(job: job)
            XCTFail("Expected the failing preprocessing command to throw")
        } catch let error as NerfstudioSplatTrainer.TrainerError {
            guard case .processFailed = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertFalse(trainer.isRunning)
    }

    func testTrainerTaskCancellationTerminatesActiveSubprocess() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("trainer-cancel-\(UUID())", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let images = root.appendingPathComponent("images", isDirectory: true)
        try fm.createDirectory(at: images, withIntermediateDirectories: true)
        try writeTestPNG(to: images.appendingPathComponent("frame.png"))
        let childPIDURL = root.appendingPathComponent("child.pid")
        let blocking = try command(named: "blocking", in: root, script: """
        #!/bin/sh
        sleep 30 &
        echo $! > "\(childPIDURL.path)"
        wait
        """)
        let runtime = NerfstudioSplatTrainer.Runtime(
            processDataURL: blocking,
            trainURL: URL(fileURLWithPath: "/usr/bin/true"),
            exportURL: URL(fileURLWithPath: "/usr/bin/true"),
            colmapURL: URL(fileURLWithPath: "/usr/bin/true")
        )
        let trainer = NerfstudioSplatTrainer(runtime: runtime)
        let job = NerfstudioSplatTrainer.Job(
            inputImagesURL: images,
            workingDirectory: root.appendingPathComponent("work", isDirectory: true),
            scanID: UUID()
        )
        let task = Task { try await trainer.train(job: job) }
        for _ in 0..<40 where !fm.fileExists(atPath: childPIDURL.path) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let childPID = try XCTUnwrap(
            Int32(String(contentsOf: childPIDURL).trimmingCharacters(in: .whitespacesAndNewlines))
        )

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertFalse(trainer.isRunning)
            XCTAssertEqual(trainer.stage, .idle)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(kill(childPID, 0), -1, "Trainer descendant should not survive cancellation")
        XCTAssertEqual(errno, ESRCH)
    }

    func testScanDirectoryCommitReplacesWholeRevision() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("scan-commit-\(UUID())", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let final = root.appendingPathComponent("scan", isDirectory: true)
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try fm.createDirectory(at: final, withIntermediateDirectories: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: final.appendingPathComponent("model.usdz"))
        try Data("obsolete".utf8).write(to: final.appendingPathComponent("old-preview.ply"))
        try Data("new".utf8).write(to: staging.appendingPathComponent("model.usdz"))
        try Data("manifest".utf8).write(to: staging.appendingPathComponent("manifest.json"))

        try ComputeCoordinator.commitScanDirectory(staging, to: final)

        XCTAssertEqual(try String(contentsOf: final.appendingPathComponent("model.usdz")), "new")
        XCTAssertTrue(fm.fileExists(atPath: final.appendingPathComponent("manifest.json").path))
        XCTAssertFalse(fm.fileExists(atPath: final.appendingPathComponent("old-preview.ply").path))
    }

    func testOlderManifestDefaultsPreviewKindToGeometry() throws {
        let json = """
        {
          "scanID": "12345678-1234-5678-9ABc-123456789ABC",
          "captureModeRaw": "Object",
          "detailTier": "Medium",
          "frameCount": 0,
          "coveragePercent": 0,
          "weakSpotCount": 0
        }
        """

        let manifest = try JSONDecoder().decode(ScanAssetManifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.previewPLYKind, .geometryPreview)
    }

    private var trainedPLYHeader: String {
        """
        ply
        format binary_little_endian 1.0
        element vertex 1
        property float x
        property float y
        property float z
        property float f_dc_0
        property float f_dc_1
        property float f_dc_2
        property float opacity
        property float scale_0
        property float scale_1
        property float scale_2
        property float rot_0
        property float rot_1
        property float rot_2
        property float rot_3
        end_header
        """ + "\n"
    }

    private func validTrainedPLYData() -> Data {
        var data = Data(trainedPLYHeader.utf8)
        data.append(contentsOf: repeatElement(UInt8(0x80), count: 56))
        return data
    }

    private func writeTestPNG(to url: URL) throws {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
    }

    private func command(named name: String, in directory: URL, script: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testLibrarySummaryCountsOnlyProvidedScanRecords() {
        let object = MacComputedScan(
            manifest: ScanAssetManifest(scanID: UUID(), captureMode: .object, detailTier: "Medium"),
            modelURL: URL(fileURLWithPath: "/tmp/object.usdz"),
            byteCount: 1_500_000,
            creationDate: Date()
        )
        let space = MacComputedScan(
            manifest: ScanAssetManifest(scanID: UUID(), captureMode: .space, detailTier: "Medium"),
            modelURL: URL(fileURLWithPath: "/tmp/space.usdz"),
            byteCount: 500_000,
            creationDate: Date()
        )

        let summary = MacLibrarySummary(scans: [object, space])

        XCTAssertEqual(summary.scanCount, 2)
        XCTAssertEqual(summary.objectCount, 1)
        XCTAssertEqual(summary.spaceCount, 1)
        XCTAssertEqual(summary.landscapeCount, 0)
        XCTAssertEqual(summary.totalByteCount, 2_000_000)
    }

    func testProgressMapsToStages() {
        XCTAssertEqual(ComputeCoordinator.Stage.forProgress(0.00), .ingest)
        XCTAssertEqual(ComputeCoordinator.Stage.forProgress(0.05), .ingest)
        XCTAssertEqual(ComputeCoordinator.Stage.forProgress(0.20), .sparse)
        XCTAssertEqual(ComputeCoordinator.Stage.forProgress(0.50), .dense)
        XCTAssertEqual(ComputeCoordinator.Stage.forProgress(0.75), .mesh)
        XCTAssertEqual(ComputeCoordinator.Stage.forProgress(0.90), .texture)
        XCTAssertEqual(ComputeCoordinator.Stage.forProgress(0.99), .optimize)
    }

    func testStageOrderingMonotonic() {
        let order = ComputeCoordinator.Stage.allCases
        XCTAssertEqual(order.first, .waiting)
        XCTAssertEqual(order.last, .done)
        // forProgress never returns waiting/done (those are set explicitly by the coordinator)
        for p in stride(from: 0.0, through: 1.0, by: 0.05) {
            let s = ComputeCoordinator.Stage.forProgress(p)
            XCTAssertNotEqual(s, .waiting)
            XCTAssertNotEqual(s, .done)
        }
    }

    func testLabels() {
        XCTAssertEqual(ComputeCoordinator.Stage.done.label, "Complete")
        XCTAssertEqual(ComputeCoordinator.Stage.dense.label, "Dense reconstruction")
    }
}

@MainActor
final class MacStateMachineTests: XCTestCase {
    func testSharedStateMachineWorksOnMac() {
        let sm = ProcessingStateMachine()
        sm.send(.startCapture(.object))
        XCTAssertEqual(sm.state, .capturing(mode: .object))
    }
}
