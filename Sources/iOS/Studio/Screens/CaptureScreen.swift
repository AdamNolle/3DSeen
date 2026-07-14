import SwiftUI
import SwiftData
import AVFoundation

/// Routed live-capture step for the Studio wizard. Mode and detail selection remain visible and
/// revisitable before this screen requests camera access and starts the selected capture engine.
struct CaptureScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var model: StudioModel
    @EnvironmentObject private var stateMachine: ProcessingStateMachine
    @State private var isPreparing = false
    @State private var isReady = false
    @State private var didPersist = false

    private var selectedInfo: CaptureModeInfo {
        STUDIO_MODES.first { $0.id == model.selectedCaptureModeID } ?? STUDIO_MODES[0]
    }

    private var captureMode: CaptureMode { selectedInfo.captureMode }

    var body: some View {
        Group {
            if isReady {
                CaptureCoordinatorView(captureMode: captureMode, onCancel: cancelCapture)
            } else {
                preparationView
            }
        }
        .task { await prepareCapture() }
        .onReceive(stateMachine.$state) { state in
            switch state {
            case .packagingScan where !didPersist:
                didPersist = true
                Task { await persistCompletedCapture() }
            default:
                break
            }
        }
    }

    private var preparationView: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                if isPreparing {
                    ProgressView().controlSize(.large)
                    Text("Preparing \(selectedInfo.name) capture")
                        .font(.sf(18, .semibold))
                        .foregroundStyle(theme.ink)
                } else {
                    StIcon(name: selectedInfo.icon, size: 34, color: theme.accentText)
                    Text("\(selectedInfo.name) capture is not running")
                        .font(.sf(20, .bold))
                        .foregroundStyle(theme.ink)
                    StButton(title: "Back to Detail", kind: .secondary, icon: "back") {
                        model.go(.quality)
                    }
                }
            }
            .padding(28)
        }
    }

    @MainActor
    private func prepareCapture() async {
        guard !isPreparing else { return }
        isPreparing = true
        isReady = false
        didPersist = false
        defer { isPreparing = false }

        let initialAvailability = CaptureAvailability.status(for: captureMode)
        guard initialAvailability.isAvailable else {
            failPreparation(initialAvailability.message ?? "Capture is not available on this device.")
            return
        }

        guard await requestCameraAccessIfNeeded() else {
            failPreparation("Camera access is required to start a scan. Allow 3DSeen to use the camera in Settings.")
            return
        }

        let updatedAvailability = CaptureAvailability.status(for: captureMode)
        guard updatedAvailability.isAvailable else {
            failPreparation(updatedAvailability.message ?? "Capture is not available on this device.")
            return
        }

        stateMachine.send(.reset)
        isReady = true
    }

    @MainActor
    private func failPreparation(_ message: String) {
        stateMachine.send(.errorOccurred(message))
    }

    private func requestCameraAccessIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    @MainActor
    private func cancelCapture() {
        stateMachine.send(.reset)
        isReady = false
        model.go(.quality)
    }

    @MainActor
    private func persistCompletedCapture() async {
        let scanDataURL = stateMachine.lastScanDataURL
        let frameCount = scanDataURL.map { CaptureArchiveInspector.imageFrameCount(in: $0) } ?? 0
        let capturedMode = stateMachine.activeCaptureMode ?? captureMode
        let session = ScanSession(
            captureMode: capturedMode,
            name: "\(capturedMode.rawValue) Scan",
            sizeMB: 0,
            tier: model.selectedDetailTier.capitalized,
            tone: tone(for: capturedMode),
            triangles: "Awaiting compute",
            captureStatus: .captured,
            computeStatus: .notStarted,
            frameCount: frameCount,
            coveragePercent: 0,
            weakSpotCount: 0
        )

        do {
            guard let scanDataURL else { throw CocoaError(.fileNoSuchFile) }
            let store = try ScanAssetStore()
            let persistedURL = try store.importCapture(from: scanDataURL, for: session.id)
            session.sizeMB = Self.sizeMB(for: persistedURL)
            if capturedMode != .space {
                session.captureQualityReport = await Task.detached(priority: .userInitiated) {
                    CaptureQualityAnalyzer.analyze(archive: persistedURL)
                }.value
            }

            if capturedMode == .space, persistedURL.pathExtension.lowercased() == "usdz" {
                session.markComputed(modelURL: persistedURL, usdzURL: persistedURL)
                session.triangles = ModelGeometryInspector.inspect(modelURL: persistedURL)?.formattedTriangleCount
                    ?? "Unavailable"
                session.captureStatusRaw = ScanCaptureStatus.captured.rawValue
            } else {
                session.markPackaged(rawArchiveURL: persistedURL)
            }

            try store.writeManifest(try store.manifest(for: session))
            modelContext.insert(session)
            model.activeScanID = session.id
            try modelContext.save()
            model.go(.review)
        } catch {
            stateMachine.send(.errorOccurred("Unable to save the captured scan: \(error.localizedDescription)"))
        }
    }

    private func tone(for mode: CaptureMode) -> String {
        switch mode {
        case .space: return "graphite"
        case .landscape: return "slate"
        case .object, .autoPilot: return "bone"
        }
    }

    private static func sizeMB(for url: URL?) -> Int {
        guard let url else { return 0 }
        let fileManager = FileManager.default
        if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber {
            return max(1, Int((size.doubleValue / 1_000_000).rounded()))
        }
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var bytes = 0
        for case let fileURL as URL in enumerator {
            bytes += ((try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return bytes == 0 ? 0 : max(1, Int((Double(bytes) / 1_000_000).rounded()))
    }
}
