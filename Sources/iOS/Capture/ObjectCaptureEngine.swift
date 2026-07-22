import ARKit
import RealityKit
import SwiftUI

struct ObjectCaptureEngine: View {
    @EnvironmentObject private var stateMachine: ProcessingStateMachine
    @StateObject private var capture: GuidedObjectCaptureController
    @State private var showsDetails = false
    let attemptID: UUID

    init(attemptID: UUID, recommendedFrameCount: Int = 48) {
        self.attemptID = attemptID
        _capture = StateObject(wrappedValue: GuidedObjectCaptureController(
            recommendedFrameCount: recommendedFrameCount
        ))
    }

    var body: some View {
        ZStack {
            GuidedObjectARView(controller: capture).ignoresSafeArea()
            GuidedTrackingOverlay(snapshot: capture.snapshot)
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                Spacer()
                controls
            }
        }
        .background(Color.black)
        .onAppear { capture.start() }
        .onDisappear { capture.stop(discardUnsealedCapture: true) }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle).font(.headline)
                    Text(capture.snapshot.instruction)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Text("\(capture.snapshot.frameCount)")
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .accessibilityLabel("\(capture.snapshot.frameCount) photos saved")
            }

            VStack(spacing: 4) {
                ProgressView(value: captureProgress)
                    .tint(Color(red: 0.38, green: 0.72, blue: 0.98))
                HStack {
                    Text("Photo set")
                    Spacer()
                    Text("\(capture.snapshot.frameCount) of \(capture.snapshot.recommendedFrameCount) recommended")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Photo set progress")
            .accessibilityValue("\(capture.snapshot.frameCount) of \(capture.snapshot.recommendedFrameCount) recommended photos")

            if showsDetails {
                HStack {
                    Label(
                        capture.snapshot.isSubjectLocked ? "subject locked" : "finding subject",
                        systemImage: capture.snapshot.isSubjectLocked ? "lock.fill" : "lock.open"
                    )
                    Spacer()
                    Label(
                        capture.snapshot.pointSource?.rawValue ?? capture.snapshot.trackingStatus,
                        systemImage: "circle.grid.cross"
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if capture.snapshot.phase == .failed {
                HStack(spacing: 10) {
                    Button(action: capture.retry) {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: finish) {
                        Label("Finish", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(capture.snapshot.frameCount == 0)
                }
            } else {
                captureControls
            }

            Button(showsDetails ? "Hide scan details" : "Show scan details") {
                withAnimation(.easeInOut(duration: 0.2)) { showsDetails.toggle() }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .accessibilityElement(children: .contain)
    }

    private var captureControls: some View {
        HStack(spacing: 10) {
                Button {
                    capture.setAutoCaptureEnabled(!capture.snapshot.isAutoCaptureEnabled)
                } label: {
                    Label(
                        capture.snapshot.isAutoCaptureEnabled ? "Pause Auto" : "Resume Auto",
                        systemImage: capture.snapshot.isAutoCaptureEnabled ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(capture.snapshot.isFinishing)

                Button(action: capture.captureManually) {
                    Label("Photo", systemImage: "camera.shutter.button")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(capture.snapshot.isFinishing)

                Button(action: finish) {
                    Label("Finish", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(capture.snapshot.frameCount == 0 || capture.snapshot.isFinishing)
        }
    }

    private var captureProgress: Double {
        min(1, Double(capture.snapshot.frameCount) / Double(capture.snapshot.recommendedFrameCount))
    }

    private var statusTitle: String {
        switch capture.snapshot.phase {
        case .starting: return "Starting camera"
        case .seekingSubject: return "Finding your object"
        case .capturing: return "Object detected"
        case .finalizing: return "Saving scan"
        case .failed: return "Capture needs attention"
        }
    }

    private var statusIcon: String {
        capture.snapshot.phase == .capturing ? "scope" : "viewfinder"
    }

    private var statusColor: Color {
        capture.snapshot.phase == .capturing
            ? Color(red: 0.38, green: 0.72, blue: 0.98)
            : .white
    }

    private func finish() {
        capture.finish { result in
            switch result {
            case .success(let folder):
                stateMachine.send(.finishCapture(scanDataURL: folder, attemptID: attemptID))
            case .failure(let error):
                stateMachine.send(.errorOccurred(error.localizedDescription))
            }
        }
    }
}

private struct GuidedTrackingOverlay: View {
    let snapshot: GuidedScanSnapshot

    var body: some View {
        Canvas { context, _ in
            if let bounds = snapshot.subjectBounds {
                context.stroke(
                    Path(roundedRect: bounds, cornerRadius: 20),
                    with: .color(.white.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 2, dash: [9, 7])
                )
            }
            for point in snapshot.points {
                let rect = CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.86)))
                context.stroke(Path(ellipseIn: rect), with: .color(.blue.opacity(0.55)), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct GuidedObjectARView: UIViewRepresentable {
    let controller: GuidedObjectCaptureController

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = controller.session
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        controller.updatePresentation(
            viewportSize: view.bounds.size,
            orientation: view.window?.windowScene?.interfaceOrientation ?? .portrait
        )
    }
}
