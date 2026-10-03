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
    @State private var preparationErrorMessage: String?
    @State private var captureAttemptID = UUID()
    @State private var persistenceTask: Task<Void, Never>?

    private var selectedInfo: CaptureModeInfo {
        STUDIO_MODES.first { $0.id == model.selectedCaptureModeID } ?? STUDIO_MODES[0]
    }

    private var captureMode: CaptureMode { selectedInfo.captureMode }

    var body: some View {
        Group {
            if isReady {
                CaptureCoordinatorView(
                    captureMode: captureMode,
                    attemptID: captureAttemptID,
                    recommendedObjectFrameCount: recommendedObjectFrameCount,
                    onCancel: cancelCapture
                )
            } else {
                preparationView
            }
        }
        .task { await prepareCapture() }
        .onReceive(stateMachine.$state) { state in
            guard case .packagingScan = state,
                  !didPersist,
                  let completion = stateMachine.lastCaptureCompletion,
                  completion.attemptID == captureAttemptID else { return }
            didPersist = true
            persistenceTask?.cancel()
            persistenceTask = Task { await persistCompletedCapture(completion) }
        }
        .onDisappear { persistenceTask?.cancel() }
    }

    private var preparationView: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                if isPreparing {
                    ProgressView().controlSize(.large)
                    Text("Getting the camera ready")
                        .font(.sf(18, .semibold))
                        .foregroundStyle(theme.ink)
                } else {
                    StIcon(name: selectedInfo.icon, size: 34, color: theme.accentText)
                    Text(
                        preparationErrorMessage == nil
                            ? "The scanner isn't running"
                            : "Capture isn't available yet"
                    )
                        .font(.sf(20, .bold))
                        .foregroundStyle(theme.ink)
                    if let preparationErrorMessage {
                        Text(preparationErrorMessage)
                            .font(.sf(15, .regular))
                            .foregroundStyle(theme.text2)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("capture.preparation.error")
                    }
                    StButton(title: "Back to Result", kind: .secondary, icon: "back") {
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
        preparationErrorMessage = nil
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
        captureAttemptID = UUID()
        isReady = true
    }

    @MainActor
    private func failPreparation(_ message: String) {
        stateMachine.send(.reset)
        preparationErrorMessage = message
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
        persistenceTask?.cancel()
        persistenceTask = nil
        stateMachine.send(.reset)
        isReady = false
        model.go(.quality)
    }

    @MainActor
    private func persistCompletedCapture(_ completion: CaptureCompletion) async {
        let scanDataURL = completion.scanDataURL
        defer { try? GuidedCaptureTemporarySource.discardIfOwned(scanDataURL) }
        let frameCount = CaptureArchiveInspector.imageFrameCount(in: scanDataURL)
        let capturedMode = completion.mode
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

        var store: ScanAssetStore?
        do {
            try Task.checkCancellation()
            let resolvedStore = try ScanAssetStore()
            store = resolvedStore
            let persistedURL: URL
            var surfaceModelURL: URL?
            if capturedMode == .space || capturedMode == .object,
                FileManager.default.fileExists(atPath: scanDataURL.appendingPathComponent(LiDARCaptureBundle.reportName).path) {
                let scanID = session.id
                let imported = try await Task.detached(priority: .userInitiated) {
                    try LiDARCaptureBundle.importCapture(from: scanDataURL, scanID: scanID, store: resolvedStore)
                }.value
                try Task.checkCancellation()
                persistedURL = imported.archiveURL
                surfaceModelURL = imported.modelURL
                session.rawArchiveURL = imported.archiveURL
                session.frameCount = CaptureArchiveInspector.imageFrameCount(in: persistedURL)
            } else {
                persistedURL = try resolvedStore.importCapture(from: scanDataURL, for: session.id)
            }
            session.sizeMB = Self.sizeMB(for: surfaceModelURL?.deletingLastPathComponent() ?? persistedURL)
            if let capturedFrame = CaptureArchiveInspector.firstDecodableImageFrame(in: persistedURL) {
                session.thumbnailURL = try resolvedStore.importThumbnail(from: capturedFrame, for: session.id)
            }
            if capturedMode != .space {
                session.captureQualityReport = await Task.detached(priority: .userInitiated) {
                    CaptureQualityAnalyzer.analyze(archive: persistedURL)
                }.value
                try Task.checkCancellation()
            }

            if [.space, .object].contains(capturedMode), let modelURL = surfaceModelURL
                ?? (persistedURL.pathExtension.lowercased() == "usdz" ? persistedURL : nil) {
                session.markComputed(modelURL: modelURL, usdzURL: modelURL)
                session.triangles = ModelGeometryInspector.inspect(modelURL: modelURL)?.formattedTriangleCount
                    ?? "Unavailable"
                session.captureStatusRaw = ScanCaptureStatus.captured.rawValue
            } else {
                session.markPackaged(rawArchiveURL: persistedURL)
            }

            try resolvedStore.writeManifest(try resolvedStore.manifest(for: session))
            try Task.checkCancellation()
            modelContext.insert(session)
            try modelContext.save()
            guard !Task.isCancelled, captureAttemptID == completion.attemptID else {
                throw CancellationError()
            }
            model.activeScanID = session.id
            model.go(.review)
        } catch is CancellationError {
            modelContext.rollback()
            try? store?.discardAssets(for: session.id)
        } catch {
            modelContext.rollback()
            try? store?.discardAssets(for: session.id)
            stateMachine.send(.errorOccurred("Unable to save the captured scan: \(error.localizedDescription)"))
        }
    }

    private var recommendedObjectFrameCount: Int {
        switch model.selectedDetailTier {
        case "preview": return 30
        case "reduced": return 40
        case "full": return 64
        case "raw": return 80
        default: return 48
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
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true,
           let attributes = try? fileManager.attributesOfItem(atPath: url.path),
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
