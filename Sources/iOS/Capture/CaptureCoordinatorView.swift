import SwiftUI
import AVFoundation
import ARKit
import UIKit

/// Hosts the selected live capture engine. Auto-Pilot begins with a camera-only Vision pass,
/// then swaps into the concrete engine it selected without fabricating a scene decision.
struct CaptureCoordinatorView: View {
    @EnvironmentObject var stateMachine: ProcessingStateMachine
    @Environment(\.scenePhase) private var scenePhase
    let captureMode: CaptureMode
    let attemptID: UUID
    let recommendedObjectFrameCount: Int
    var onCancel: (() -> Void)?
    @State private var resolvedAutoPilotMode: CaptureMode?
    @State private var idleTimerLease = CaptureIdleTimerLease()

    init(
        captureMode: CaptureMode,
        attemptID: UUID,
        recommendedObjectFrameCount: Int = 48,
        onCancel: (() -> Void)? = nil
    ) {
        self.captureMode = captureMode
        self.attemptID = attemptID
        self.recommendedObjectFrameCount = recommendedObjectFrameCount
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            captureContent
            closeButton
        }
        .navigationBarBackButtonHidden()
        .onAppear {
            if stateMachine.state != .capturing(mode: captureMode)
                || stateMachine.activeCaptureAttemptID != attemptID {
                stateMachine.send(.startCapture(captureMode, attemptID: attemptID))
            }
            updateIdleTimerLease()
        }
        .onChange(of: shouldKeepDisplayAwake) { _, _ in updateIdleTimerLease() }
        .onDisappear(perform: restoreIdleTimer)
    }

    private var shouldKeepDisplayAwake: Bool {
        CaptureDisplayAwakePolicy.shouldKeepAwake(
            state: stateMachine.state,
            activeAttemptID: stateMachine.activeCaptureAttemptID,
            attemptID: attemptID,
            isSceneActive: scenePhase == .active
        )
    }

    private func updateIdleTimerLease() {
        guard let value = idleTimerLease.update(
            isCapturing: shouldKeepDisplayAwake,
            currentValue: UIApplication.shared.isIdleTimerDisabled
        ) else { return }
        UIApplication.shared.isIdleTimerDisabled = value
    }

    private func restoreIdleTimer() {
        guard let value = idleTimerLease.restore() else { return }
        UIApplication.shared.isIdleTimerDisabled = value
    }

    @ViewBuilder private var captureContent: some View {
        switch captureMode {
        case .autoPilot:
            if let resolvedAutoPilotMode {
                captureEngine(for: resolvedAutoPilotMode)
            } else {
                AutoPilotCaptureEngine(
                    onResolved: { mode in
                        resolvedAutoPilotMode = mode
                        stateMachine.send(.autoPilotResolved(mode, attemptID: attemptID))
                    },
                    onFailure: { message in
                        stateMachine.send(.errorOccurred(message))
                    }
                )
            }
        default:
            captureEngine(for: captureMode)
        }
    }

    @ViewBuilder private func captureEngine(for mode: CaptureMode) -> some View {
        switch mode {
        case .object:
            ObjectCaptureEngine(
                attemptID: attemptID,
                recommendedFrameCount: recommendedObjectFrameCount
            )
        case .space:
            RoomCaptureEngine(attemptID: attemptID).id(attemptID)
        case .landscape:
            LandscapeCaptureEngine(attemptID: attemptID)
        case .autoPilot:
            EmptyView()
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Button {
                    if let onCancel {
                        onCancel()
                    } else {
                        stateMachine.send(.reset)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .padding()
                Spacer()
            }
            Spacer()
        }
    }
}

/// A short live-camera Vision pass that resolves a capture mode from stable classifications.
private struct AutoPilotCaptureEngine: View {
    @StateObject private var controller = AutoPilotCaptureController()
    let onResolved: (CaptureMode) -> Void
    let onFailure: (String) -> Void

    var body: some View {
        ZStack {
            AutoPilotCameraPreview(session: controller.session)
                .ignoresSafeArea()

            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text(controller.statusText)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.black.opacity(0.52), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 16)
            .padding(.top, 64)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Analyzing live scene")
            .accessibilityValue(controller.statusText)
        }
        .onAppear {
            controller.onResolved = onResolved
            controller.onFailure = onFailure
            controller.start()
        }
        .onDisappear { controller.stop() }
    }
}

private final class AutoPilotCaptureController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published private(set) var statusText = "Detecting scan type"

    var onResolved: ((CaptureMode) -> Void)?
    var onFailure: ((String) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.adamnolle.3DSeen.autopilot-session")
    private let frameQueue = DispatchQueue(label: "com.adamnolle.3DSeen.autopilot-frames")
    private let vision = AutoPilotVisionManager()
    private var configured = false
    private var isResolving = false
    private var lastClassificationTime: CFTimeInterval = 0
    private var lastSuggestedMode: CaptureMode?
    private var consecutiveSuggestions = 0
    private var timeoutWorkItem: DispatchWorkItem?

    func start() {
        frameQueue.async { [weak self] in
            guard let self else { return }
            self.isResolving = false
            self.lastClassificationTime = 0
            self.lastSuggestedMode = nil
            self.consecutiveSuggestions = 0
            self.timeoutWorkItem?.cancel()
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configureIfNeeded()
                guard !self.session.isRunning else { return }
                self.session.startRunning()
                self.frameQueue.async { self.scheduleObjectFallback() }
            } catch {
                self.publishFailure("Auto-Pilot could not start the camera: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        frameQueue.async { [weak self] in
            self?.isResolving = true
            self?.timeoutWorkItem?.cancel()
            self?.timeoutWorkItem = nil
        }
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
    }

    private func configureIfNeeded() throws {
        guard !configured else { return }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw NSError(domain: "3DSeen.AutoPilot", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No rear camera is available."])
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw NSError(domain: "3DSeen.AutoPilot", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The camera input could not be configured."])
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(output) else {
            throw NSError(domain: "3DSeen.AutoPilot", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "The camera output could not be configured."])
        }
        session.addOutput(output)
        configured = true
    }

    private func scheduleObjectFallback() {
        guard !isResolving else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.resolve(.object, detail: "Starting Object capture")
        }
        timeoutWorkItem = workItem
        frameQueue.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isResolving,
              CACurrentMediaTime() - lastClassificationTime > 0.65,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastClassificationTime = CACurrentMediaTime()

        let suggestion = vision.suggestion(for: pixelBuffer)
        let mode = AutoPilotVisionManager.resolvedMode(for: suggestion, supportedModes: supportedModes)
        consume(suggestion: suggestion, resolvedMode: mode)
    }

    private var supportedModes: Set<CaptureMode> {
        var modes: Set<CaptureMode> = [.object]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) { modes.insert(.space) }
        if ARWorldTrackingConfiguration.isSupported { modes.insert(.landscape) }
        return modes
    }

    private func consume(suggestion: AutoPilotVisionManager.Suggestion, resolvedMode: CaptureMode) {
        guard !isResolving else { return }
        DispatchQueue.main.async { [weak self] in
            self?.statusText = "Considering \(suggestion.label)"
        }
        if lastSuggestedMode == resolvedMode {
            consecutiveSuggestions += 1
        } else {
            lastSuggestedMode = resolvedMode
            consecutiveSuggestions = 1
        }

        guard consecutiveSuggestions >= 3 else { return }
        resolve(resolvedMode, detail: "Starting \(resolvedMode.rawValue) scan")
    }

    private func resolve(_ mode: CaptureMode, detail: String) {
        guard !isResolving else { return }
        isResolving = true
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        DispatchQueue.main.async { [weak self] in self?.statusText = detail }
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.onResolved?(mode)
        }
    }

    private func publishFailure(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onFailure?(message) }
    }
}

private struct AutoPilotCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("PreviewView must use AVCaptureVideoPreviewLayer.")
        }
        return previewLayer
    }
}
