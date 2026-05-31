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

            VStack {
                HStack {
                    Image(systemName: "house").font(.system(size: 24))
                    Text("Space Capture").font(.headline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(.ultraThinMaterial).clipShape(Capsule())
                .padding(.top, 10)

                Spacer()

                if controller.isProcessing {
                    ProgressView("Building room model…")
                        .padding().background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 15)).padding(.bottom, 20)
                } else {
                    Text("Pan the device across walls, windows, and furniture.")
                        .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.white)
                        .padding().background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 15)).padding(.bottom, 20)
                }

                Button {
                    controller.finish()
                } label: {
                    Text("Finish Space Scan")
                        .font(.headline).frame(maxWidth: .infinity).padding()
                        .background(Color.green.opacity(0.9)).foregroundColor(.white)
                        .clipShape(Capsule()).shadow(color: .green.opacity(0.3), radius: 10, y: 5)
                }
                .disabled(controller.isProcessing)
                .padding(.horizontal, 40).padding(.bottom, 40)
            }
        }
        .onAppear {
            controller.onExported = { url in
                stateMachine.send(.finishCapture(scanDataURL: url))
            }
            controller.start()
        }
        .onDisappear { controller.stop() }
    }
}

/// Owns the RoomPlan session lifecycle and USDZ export.
final class RoomCaptureController: NSObject, ObservableObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    private let logger = Logger(subsystem: "com.adamnolle.3DSeen", category: "RoomPlan")
    let roomCaptureView: RoomCaptureView
    private var finalResults: CapturedRoom?

    @Published var isProcessing = false
    var onExported: ((URL) -> Void)?

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
        let config = RoomCaptureSession.Configuration()
        roomCaptureView.captureSession.run(configuration: config)
    }

    func finish() {
        isProcessing = true
        roomCaptureView.captureSession.stop()
    }

    func stop() {
        roomCaptureView.captureSession.stop()
    }

    // Allow the view to post-process the raw scan into a CapturedRoom.
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        return true
    }

    // CapturedRoom is ready — export USDZ.
    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        finalResults = processedResult
        guard error == nil else {
            logger.error("RoomPlan processing error: \(error!.localizedDescription)")
            isProcessing = false
            return
        }
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("space-\(UUID().uuidString)")
                .appendingPathExtension("usdz")
            try processedResult.export(to: url, exportOptions: .parametric)
            logger.info("Exported room USDZ to \(url.lastPathComponent)")
            DispatchQueue.main.async {
                self.isProcessing = false
                self.onExported?(url)
            }
        } catch {
            logger.error("RoomPlan export failed: \(error.localizedDescription)")
            DispatchQueue.main.async { self.isProcessing = false }
        }
    }
}

/// Hosts the UIKit `RoomCaptureView` in SwiftUI.
struct RoomCaptureContainer: UIViewRepresentable {
    let controller: RoomCaptureController
    func makeUIView(context: Context) -> RoomCaptureView { controller.roomCaptureView }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}
