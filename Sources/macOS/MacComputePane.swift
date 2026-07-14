import SwiftUI

/// The Mac compute dashboard reports only coordinator state and photogrammetry progress. It does
/// not manufacture GPU, thermal, ETA, or reconstruction-quality telemetry that macOS does not
/// provide through the compute API.
struct MacComputePane: View {
    @Environment(\.theme) private var theme
    @Binding var section: MacSection
    @ObservedObject var compute: ComputeCoordinator
    @ObservedObject var network: NetworkHandoffManager

    private var currentName: String { compute.outputURL?.deletingPathExtension().lastPathComponent ?? "Incoming scan" }

    var body: some View {
        VStack(spacing: 0) {
            MacTopBar {
                MacBackButton(label: "Library") { section = .library }
                MacToolbarDivider()
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text("Compute · \(currentName)").font(.sf(15, .bold)).foregroundStyle(theme.ink).lineLimit(1)
                StTextChip(text: statusText)
                Spacer(minLength: 0)
                if compute.queuedRemoteJobCount > 0 {
                    StButton(title: "Cancel queued (\(compute.queuedRemoteJobCount))", kind: .secondary, size: .sm) {
                        compute.cancelQueuedRemoteJobs()
                    }
                    .accessibilityHint("Cancels every accepted handoff that has not started processing.")
                }
                if compute.activeRemoteJobID != nil {
                    StButton(title: "Cancel active", kind: .secondary, size: .sm) {
                        compute.cancelActiveRemoteJob()
                    }
                    .accessibilityHint("Stops reconstruction and notifies the sending device.")
                }
                if compute.peerName != "—" {
                    StChip(tone: .neutral) { StIcon(name: "laptop", size: 13, color: theme.text2); Text(compute.peerName) }
                }
            }

            HStack(spacing: 0) {
                pipeline.frame(width: 330)
                StRule(vertical: true)
                preview.frame(maxWidth: .infinity)
                StRule(vertical: true)
                eventLog.frame(width: 340)
            }
        }
    }

    private var statusText: String {
        if compute.selectedSplatOutput == .trainedSplat, compute.splatTrainer.isRunning {
            return compute.splatTrainerStage.label.uppercased()
        }
        switch compute.stage {
        case .waiting: return "WAITING FOR HANDOFF"
        case .done: return "COMPLETE"
        default: return "\(Int(compute.progress * 100))%"
        }
    }

    private var statusColor: Color {
        switch compute.stage {
        case .waiting: return theme.text3
        case .done: return theme.good
        default: return theme.accent
        }
    }

    private var pipeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            StLabel(text: "Pipeline · RealityKit")
            peerConnections.padding(.top, 12)
            splatOutputPicker.padding(.top, 16)
            VStack(alignment: .leading, spacing: 0) {
                let stages = ComputeCoordinator.Stage.allCases.filter { $0 != .waiting && $0 != .done }
                ForEach(Array(stages.enumerated()), id: \.element) { index, stage in
                    pipelineRow(index: index, stage: stage, isLast: index == stages.count - 1)
                }
            }
            .padding(.top, 16)
            Spacer()
            if compute.receivedFrames > 0 {
                StCard(radius: 8, pad: 14, inset: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        StLabel(text: "Received capture")
                        Text("\(compute.receivedFrames) image frames").font(.sf(16, .bold)).foregroundStyle(theme.ink)
                    }
                }
            }
        }
        .padding(22)
        .frame(maxHeight: .infinity)
        .background(theme.card2)
    }

    private var peerConnections: some View {
        VStack(alignment: .leading, spacing: 8) {
            StLabel(text: "Capture devices")
            if network.discoveredPeers.isEmpty {
                Text("No compatible iPhone or iPad discovered")
                    .font(.sf(12)).foregroundStyle(theme.text3)
            } else {
                ForEach(network.discoveredPeers) { peer in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(peer.displayName).font(.sf(13, .semibold)).foregroundStyle(theme.ink)
                            Text(peer.connectionState.rawValue.capitalized)
                                .font(.mono(9.5)).foregroundStyle(theme.text3)
                        }
                        Spacer(minLength: 6)
                        if peer.connectionState == .connected || peer.connectionState == .authenticated {
                            StTextChip(text: "CONNECTED")
                        } else {
                            StButton(title: "Connect", kind: .secondary, size: .sm) {
                                network.invite(peerID: peer.installationID)
                            }
                        }
                    }
                    .padding(9)
                    .background(RoundedRectangle(cornerRadius: 9).fill(theme.fieldFill))
                }
            }
        }
    }

    private var splatOutputPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            StLabel(text: "Splat output")
            Picker("Splat output", selection: $compute.selectedSplatOutput) {
                ForEach(ComputeCoordinator.SplatOutput.allCases) { output in
                    Text(output.label).tag(output)
                }
            }
            .pickerStyle(.segmented)
            .disabled(compute.isProcessing)
            Text(splatOutputDescription)
                .font(.sf(11.5)).foregroundStyle(theme.text3).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var splatOutputDescription: String {
        switch compute.selectedSplatOutput {
        case .geometryPreview:
            return "Vertex-derived PLY preview. It is not a trained radiance field."
        case .trainedSplat:
            return compute.trainedSplatAvailable
                ? "Runs local COLMAP and Nerfstudio on this Mac after reconstruction."
                : "Unavailable: install the configured local Nerfstudio and COLMAP runtime."
        }
    }

    private func pipelineRow(index: Int, stage: ComputeCoordinator.Stage, isLast: Bool) -> some View {
        let isDone = compute.stage.rawValue > stage.rawValue || compute.stage == .done
        let active = compute.stage == stage
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(isDone ? theme.good : active ? theme.accentSoft : theme.fieldFill).frame(width: 26, height: 26)
                    if isDone {
                        StIcon(name: "check", size: 13, color: .white, weight: .heavy)
                    } else if active {
                        Circle().fill(theme.accent).frame(width: 8, height: 8)
                    } else {
                        Text("\(index + 1)").font(.sf(11, .bold)).foregroundStyle(theme.text3)
                    }
                }
                if !isLast { Rectangle().fill(isDone ? theme.good : theme.line).frame(width: 2, height: 26) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(stage.label).font(.sf(14, .semibold)).foregroundStyle(isDone || active ? theme.ink : theme.text2)
                Text(stageDescription(stage)).font(.sf(12)).foregroundStyle(theme.text3)
                if active { StMeter(value: compute.progress, height: 5).frame(width: 185).padding(.top, 4) }
            }
            .padding(.bottom, isLast ? 0 : 18)
        }
    }

    private func stageDescription(_ stage: ComputeCoordinator.Stage) -> String {
        switch stage {
        case .ingest: return "Reading capture files"
        case .sparse: return "Estimating camera positions"
        case .dense: return "Reconstructing depth"
        case .mesh: return "Building mesh"
        case .texture: return "Writing texture data"
        case .optimize: return "Packaging USDZ"
        case .waiting, .done: return ""
        }
    }

    private var preview: some View {
        ZStack(alignment: .topLeading) {
            MacModelStage(assetURL: compute.stage == .done ? compute.outputURL : nil)
            StGlass(radius: 8) {
                Text(compute.stage == .done ? "Computed model" : statusText)
                    .font(.mono(11, .semibold)).foregroundStyle(theme.text2)
                    .padding(.horizontal, 10).padding(.vertical, 7)
            }
            .padding(18)
        }
        .padding(22)
    }

    private var eventLog: some View {
        VStack(alignment: .leading, spacing: 14) {
            StLabel(text: "Compute events")
            if compute.log.isEmpty {
                Text("Waiting for a scan handoff from a connected iPhone or iPad.")
                    .font(.sf(13)).foregroundStyle(theme.text3)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(compute.log.suffix(12).enumerated()), id: \.offset) { _, entry in
                            HStack(alignment: .top, spacing: 9) {
                                Text(entry.time).font(.mono(10)).foregroundStyle(theme.text4).frame(width: 54, alignment: .leading)
                                Text(entry.message).font(.sf(12.5)).foregroundStyle(theme.text2)
                            }
                        }
                    }
                }
            }
            Spacer()
            StButton(title: "Open result", kind: .accent, icon: "cube", full: true) { section = .viewer }
                .disabled(compute.outputURL == nil || compute.stage != .done)
        }
        .padding(22)
        .background(theme.card2)
    }
}
