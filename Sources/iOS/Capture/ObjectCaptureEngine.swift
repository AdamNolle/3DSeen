import SwiftUI
import RealityKit
import os

struct ObjectCaptureEngine: View {
    @EnvironmentObject var stateMachine: ProcessingStateMachine

    // We instantiate the actual iOS 17 ObjectCaptureSession
    @State private var session = ObjectCaptureSession()
    @State private var captureDirectory: URL?
    @State private var isFinishing = false
    @State private var finishTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // The native RealityKit Capture View driving the AR session
            ObjectCaptureView(session: session)
                .ignoresSafeArea()

            LiveCaptureHUD(status: captureStatus, onPrimaryAction: advanceCapture, onFinish: finishCapture)
                .allowsHitTesting(!isFinishing)
        }
        .onAppear {
            // Provide a directory to save images
            let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            captureDirectory = directory
            var configuration = ObjectCaptureSession.Configuration()
            configuration.checkpointDirectory = directory
            session.start(imagesDirectory: directory, configuration: configuration)
        }
        .onDisappear {
            finishTask?.cancel()
            session.cancel()
        }
    }

    private func finishCapture() {
        guard !isFinishing, let captureDirectory else { return }
        isFinishing = true
        session.finish()
        finishTask = Task {
            let result = await waitForCaptureCompletion()
            guard !Task.isCancelled else { return }
            switch result {
            case .success:
                guard CaptureArchiveInspector.containsImageFrames(in: captureDirectory) else {
                    stateMachine.send(.errorOccurred("Object Capture did not save any usable camera frames. Retake the scan and keep the object in view."))
                    isFinishing = false
                    return
                }
                stateMachine.send(.finishCapture(scanDataURL: captureDirectory))
            case .failure(let error):
                stateMachine.send(.errorOccurred("Object Capture could not finish: \(error.localizedDescription)"))
            }
            isFinishing = false
        }
    }

    private var captureStatus: LiveCaptureStatus {
        if isFinishing { return LiveCaptureStatus(mode: .object, phase: .finalizing) }
        if case .ready = session.state { return LiveCaptureStatus(mode: .object, phase: .ready) }
        if case .detecting = session.state { return LiveCaptureStatus(mode: .object, phase: .detecting) }
        if case .capturing = session.state { return LiveCaptureStatus(mode: .object, phase: .capturing) }
        return LiveCaptureStatus(mode: .object, phase: .processing)
    }

    private func advanceCapture() {
        if case .ready = session.state {
            _ = session.startDetecting()
        } else if case .detecting = session.state {
            session.startCapturing()
        }
    }

    /// Wait for ObjectCaptureSession's documented terminal state. File-size polling can observe a
    /// quiet gap between write batches and expose an incomplete capture directory.
    private func waitForCaptureCompletion() async -> Result<Void, Error> {
        switch session.state {
        case .completed:
            return .success(())
        case .failed(let error):
            return .failure(error)
        default:
            break
        }
        for await state in session.stateUpdates {
            if Task.isCancelled { return .failure(CancellationError()) }
            switch state {
            case .completed:
                return .success(())
            case .failed(let error):
                return .failure(error)
            default:
                continue
            }
        }
        return .failure(CancellationError())
    }
}
