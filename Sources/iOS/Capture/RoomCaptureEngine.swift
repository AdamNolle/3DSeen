import SwiftUI
import RoomPlan
import OSLog

/// Space capture using Apple's RoomPlan. Drives a live `RoomCaptureView`, and on finish
/// processes the `CapturedRoom` and exports a parametric USDZ for the compute/export pipeline.
struct RoomCaptureEngine: View {
    @EnvironmentObject var stateMachine: ProcessingStateMachine
    @StateObject private var controller = RoomCaptureController()

    var body: some View {
        ZStack {
            if RoomCaptureSession.isSupported {
                RoomCaptureContainer(controller: controller)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                Text("RoomPlan requires a LiDAR-equipped device.")
                    .font(.headline).foregroundStyle(.white).padding()
            }

            LiveCaptureHUD(status: captureStatus, onFinish: controller.isProcessing ? nil : controller.finish)
                .allowsHitTesting(!controller.isProcessing)
        }
        .onAppear {
            controller.onExported = { url in
                stateMachine.send(.finishCapture(scanDataURL: url))
            }
            controller.onFailure = { message in
                stateMachine.send(.errorOccurred(message))
            }
            guard RoomCaptureSession.isSupported else {
                stateMachine.send(.errorOccurred("RoomPlan requires a LiDAR-equipped iPhone or iPad."))
                return
            }
            controller.start()
        }
        .onDisappear {
            controller.onExported = nil
            controller.onFailure = nil
            controller.cancel()
        }
    }

    private var captureStatus: LiveCaptureStatus {
        LiveCaptureStatus(mode: .space, phase: controller.isProcessing ? .processing : .capturing)
    }
}

/// Owns the RoomPlan session lifecycle and USDZ export.
final class RoomCaptureController: NSObject, ObservableObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    private let logger = Logger(subsystem: "com.adamnolle.3DSeen", category: "RoomPlan")
    let roomCaptureView: RoomCaptureView
    private var finalResults: CapturedRoom?
    private var isCancelled = false

    @Published var isProcessing = false
    var onExported: ((URL) -> Void)?
    var onFailure: ((String) -> Void)?

    override init() {
        roomCaptureView = RoomCaptureView(frame: .zero)
        super.init()
        roomCaptureView.captureSession.delegate = self
        roomCaptureView.delegate = self
    }

    // RoomCaptureViewDelegate refines NSCoding; we don't archive this controller, so these are inert.
    required init?(coder: NSCoder) {
        roomCaptureView = RoomCaptureView(frame: .zero)
        super.init()
        roomCaptureView.captureSession.delegate = self
        roomCaptureView.delegate = self
    }
    func encode(with coder: NSCoder) {}

    func start() {
        isCancelled = false
        finalResults = nil
        roomCaptureView.captureSession.delegate = self
        roomCaptureView.delegate = self
        let config = RoomCaptureSession.Configuration()
        roomCaptureView.captureSession.run(configuration: config)
    }

    func finish() {
        guard !isCancelled, !isProcessing else { return }
        isProcessing = true
        roomCaptureView.captureSession.stop()
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        isProcessing = false
        roomCaptureView.delegate = nil
        roomCaptureView.captureSession.delegate = nil
        roomCaptureView.captureSession.stop()
    }

    // Allow the view to post-process the raw scan into a CapturedRoom.
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        !isCancelled && isProcessing
    }

    // CapturedRoom is ready — export USDZ.
    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        guard !isCancelled, isProcessing else { return }
        finalResults = processedResult
        guard error == nil else {
            logger.error("RoomPlan processing error: \(error!.localizedDescription)")
            publishFailure("RoomPlan could not process this scan: \(error!.localizedDescription)")
            return
        }
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("space-\(UUID().uuidString)")
                .appendingPathExtension("usdz")
            try processedResult.export(to: url, exportOptions: .parametric)
            logger.info("Exported room USDZ to \(url.lastPathComponent)")
            DispatchQueue.main.async {
                guard !self.isCancelled else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                self.isProcessing = false
                self.onExported?(url)
            }
        } catch {
            logger.error("RoomPlan export failed: \(error.localizedDescription)")
            publishFailure("RoomPlan could not export this scan: \(error.localizedDescription)")
        }
    }

    private func publishFailure(_ message: String) {
        DispatchQueue.main.async {
            guard !self.isCancelled else { return }
            self.isProcessing = false
            self.onFailure?(message)
        }
    }
}

/// Hosts the UIKit `RoomCaptureView` in SwiftUI.
struct RoomCaptureContainer: UIViewRepresentable {
    let controller: RoomCaptureController
    func makeUIView(context: Context) -> RoomCaptureView { controller.roomCaptureView }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}
