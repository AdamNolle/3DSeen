// ComputeScreen.swift — compute pipeline & Mac handoff (iPhone + iPad), ported from screens/compute.jsx
// PhoneCompute (compact) and PadCompute "Hub & spoke" (regular) self-adapt on horizontalSizeClass.

import SwiftUI
import SwiftData

// MARK: - Option data

struct ComputeOption: Identifiable {
    let id: String
    let name: String
    let icon: String
    let tag: String
    var best: Bool = false
    let stats: [(String, String, Color?)]
}

extension ComputeOption {
    /// The available render targets. Performance and battery predictions depend on hardware and
    /// input images, so this UI deliberately does not invent values before compute starts.
    static func pair(_ t: Theme, requestedTier: String) -> (mac: ComputeOption, local: ComputeOption) {
        let macTier = ComputeDetailCapability.effectiveTier(for: .macHandoff, requestedTier: requestedTier)
        let localTier = ComputeDetailCapability.effectiveTier(for: .onDevice, requestedTier: requestedTier)
        return (
            ComputeOption(id: "mac", name: "Mac handoff", icon: "laptop",
                          tag: "Requested \(macTier) output", best: false,
                          stats: [("Output", macTier, t.accentText)]),
            ComputeOption(id: "local", name: "On-device", icon: "chip",
                          tag: "RealityKit · \(localTier) output",
                          stats: [("Output", localTier, t.warn)])
        )
    }
}

// MARK: - Screen (size-class router)

struct ComputeScreen: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var sel = "mac"

    var body: some View {
        Group {
            if hSize == .regular && !dynamicTypeSize.isAccessibilitySize {
                PadComputeBody(sel: $sel)
            } else {
                PhoneComputeBody(sel: $sel)
            }
        }
    }
}

// MARK: - iPhone layout (PhoneCompute)

private struct PhoneComputeBody: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var model: StudioModel
    @EnvironmentObject private var stateMachine: ProcessingStateMachine
    @StateObject private var network = NetworkHandoffManager()
    @StateObject private var localCompute = ScanLocalComputeService()
    @Query(sort: \ScanSession.creationDate, order: .reverse) private var savedScans: [ScanSession]
    @State private var computeTask: Task<Void, Never>?
    @Binding var sel: String

    private var activeScan: ScanSession? {
        if let id = model.activeScanID, let scan = savedScans.first(where: { $0.id == id }) {
            return scan
        }
        return savedScans.first
    }

    private var isBusy: Bool {
        if computeTask != nil || localCompute.isRunning { return true }
        if case .computingOffloaded = stateMachine.state { return true }
        return false
    }

    private var scanSizeText: String {
        guard let activeScan, activeScan.sizeMB > 0 else { return "SCAN · pending" }
        return activeScan.sizeMB >= 1000
            ? "SCAN · \(String(format: "%.1f", Double(activeScan.sizeMB) / 1000)) GB"
            : "SCAN · \(activeScan.sizeMB) MB"
    }

    private var options: [ComputeOption] {
        let p = ComputeOption.pair(theme, requestedTier: activeScan?.tierRaw ?? model.selectedDetailTier)
        return [p.mac, p.local]
    }

    private var primaryActionTitle: String {
        if sel == "local", localCompute.isRunning {
            return "Computing \(Int((localCompute.progress * 100).rounded()))%"
        }
        return sel == "mac" ? "Hand off to Mac" : "Compute on device · Reduced"
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WizardHeader(step: 4, onBack: { model.go(.review) }, onClose: { model.go(.library) })
                    titleBlock
                    handoffCard.padding(.top, 14)
                    optionStack.padding(.top, 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomCTA {
                StButton(title: primaryActionTitle,
                         kind: .accent, size: .lg, icon: sel == "mac" ? "laptop" : "chip", full: true) { startCompute() }
                    .disabled(isBusy || activeScan == nil)
            }
        }
        .onReceive(localCompute.$progress) { progress in
            guard localCompute.isRunning else { return }
            stateMachine.send(.updateLocalProgress(progress))
        }
        .onDisappear {
            computeTask?.cancel()
            computeTask = nil
            localCompute.cancel()
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            StLabel(text: "Where should we render?")
            Text("Compute pipeline").font(.sf(28, .heavy)).tracking(0).foregroundStyle(theme.ink).padding(.top, 6)
            Text("On-device RealityKit produces Reduced output. A Mac handoff keeps the selected detail request.")
                .font(.sf(13.5)).foregroundStyle(theme.text2).padding(.top, 8)
        }
        .padding(.top, 18)
    }

    private var handoffCard: some View {
        StCard(radius: 22, pad: 20) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 14) {
                    HStack(alignment: .top, spacing: 18) {
                        phoneGlyph.frame(maxWidth: .infinity)
                        macGlyph.frame(maxWidth: .infinity)
                    }
                    HStack(spacing: 7) {
                        Circle()
                            .fill(network.connectedPeers.isEmpty ? theme.text3 : theme.good)
                            .frame(width: 7, height: 7)
                        Text(network.connectedPeers.isEmpty ? "NO MAC CONNECTED" : "SECURE LOCAL HANDOFF")
                            .font(.mono(9.5, .semibold))
                            .tracking(1)
                            .foregroundStyle(theme.accentText)
                    }
                }
            } else {
                HStack {
                    phoneGlyph
                    VStack(spacing: 2) {
                        HandoffArc(progress: network.transferProgress).frame(height: 54).accessibilityHidden(true)
                        Text(network.connectedPeers.isEmpty ? "NO MAC CONNECTED" : "SECURE LOCAL HANDOFF")
                            .font(.mono(9.5)).tracking(1).foregroundStyle(theme.accentText)
                    }
                    .padding(.horizontal, 6)
                    macGlyph
                }
            }
        }
        .onAppear {
            configureNetworkCallbacks()
        }
    }

    private var phoneGlyph: some View {
        DeviceGlyph(kind: .phone, width: 46, label: "This device", sub: scanSizeText, subColor: theme.accentText)
    }

    private var macGlyph: some View {
        DeviceGlyph(kind: .mac, width: 84,
                    label: network.connectedPeers.first?.displayName ?? "Mac",
                    sub: network.connectedPeers.isEmpty ? "NOT CONNECTED" : "CONNECTED",
                    subColor: theme.text3)
    }

    private func configureNetworkCallbacks() {
        network.onReceiveResultPackage = { url, _ in
            importResultPackage(url)
        }
        network.onSendError = { error in
            activeScan?.computeStatusRaw = ScanComputeStatus.failed.rawValue
            stateMachine.send(.errorOccurred("Mac handoff failed: \(error.localizedDescription)"))
        }
    }

    private func sendActiveScanToMacIfPossible() {
        guard let activeScan else {
            stateMachine.send(.errorOccurred("No active scan is ready for Mac handoff."))
            return
        }
        guard let rawArchiveURL = activeScan.rawArchiveURL else {
            activeScan.computeStatusRaw = ScanComputeStatus.failed.rawValue
            stateMachine.send(.errorOccurred("Capture package is missing for Mac handoff."))
            return
        }
        let handoffArchive: URL
        do {
            handoffArchive = try ScanHandoffArchive.package(
                rawArchiveURL,
                captureQualityReport: activeScan.captureQualityReport
            )
        } catch {
            activeScan.computeStatusRaw = ScanComputeStatus.failed.rawValue
            stateMachine.send(.errorOccurred(error.localizedDescription))
            return
        }

        guard network.sendScanToFirstPeer(
            handoffArchive,
            metadata: ScanHandoffMetadata(
                scanID: activeScan.id,
                captureMode: activeScan.captureMode,
                detailTier: activeScan.tierRaw
            )
        ) else {
            activeScan.computeStatusRaw = ScanComputeStatus.queued.rawValue
            stateMachine.send(.errorOccurred("No Mac is connected for handoff. Choose on-device compute or connect a Mac."))
            return
        }
        activeScan.computeStatusRaw = ScanComputeStatus.offloaded.rawValue
        stateMachine.send(.offloadToMac)
        stateMachine.send(.updateOffloadStatus("Sent \(handoffArchive.lastPathComponent) to Mac."))
    }

    private func importResultPackage(_ packageURL: URL) {
        defer { network.removeReceivedResource(packageURL) }
        var importedScan: ScanSession?
        do {
            let fm = FileManager.default
            let importDir = fm.temporaryDirectory.appendingPathComponent("3dseen-result-import-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: importDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: importDir) }

            let result = try ScanResultPackage().unpack(packageURL, to: importDir)
            let manifest = result.manifest
            guard let targetScan = savedScans.first(where: { $0.id == manifest.scanID }) else {
                throw CocoaError(.fileReadUnknown)
            }
            importedScan = targetScan
            let store = try ScanAssetStore()
            let destination = try store.importCapture(from: result.modelURL, for: targetScan.id)
            let previewDestination = try result.previewPLYURL.map {
                try store.importCapture(from: $0, for: targetScan.id)
            }

            targetScan.markComputed(
                modelURL: destination,
                usdzURL: destination.pathExtension.lowercased() == "usdz" ? destination : nil,
                previewPLYURL: previewDestination,
                previewPLYKind: manifest.previewPLYKind
            )
            targetScan.captureModeRaw = manifest.captureMode.rawValue
            targetScan.tierRaw = manifest.detailTier
            targetScan.frameCount = max(targetScan.frameCount, manifest.frameCount)
            targetScan.coveragePercent = max(targetScan.coveragePercent, manifest.coveragePercent)
            targetScan.weakSpotCount = manifest.weakSpotCount
            if let report = manifest.captureQualityReport {
                targetScan.captureQualityReport = report
            }
            targetScan.triangles = ModelGeometryInspector.inspect(modelURL: destination)?.formattedTriangleCount ?? "Unavailable"
            try store.writeManifest(try store.manifest(for: targetScan))
            try modelContext.save()
            if model.activeScanID == targetScan.id {
                stateMachine.send(.computeCompleted(destination))
            }
        } catch {
            importedScan?.computeStatusRaw = ScanComputeStatus.failed.rawValue
            stateMachine.send(.errorOccurred("The returned Mac result could not be matched to its source scan. \(error.localizedDescription)"))
        }
    }

    private func startCompute() {
        guard !isBusy else { return }
        guard let activeScan else {
            stateMachine.send(.errorOccurred("No active scan is ready to compute."))
            return
        }
        if sel == "mac" {
            activeScan.computeStatusRaw = ScanComputeStatus.offloaded.rawValue
            stateMachine.send(.userSelectsComputeMode(.offload))
            sendActiveScanToMacIfPossible()
        } else {
            activeScan.computeStatusRaw = ScanComputeStatus.local.rawValue
            stateMachine.send(.userSelectsComputeMode(.local))
            stateMachine.send(.startLocalCompute)
            computeTask = Task {
                await computeLocally(activeScan)
                computeTask = nil
            }
        }
    }

    private func computeLocally(_ scan: ScanSession) async {
        do {
            let output = try await localCompute.compute(scan: scan)
            try modelContext.save()
            stateMachine.send(.computeCompleted(output))
            model.go(.viewer)
        } catch is CancellationError {
            scan.computeStatusRaw = ScanComputeStatus.queued.rawValue
            try? modelContext.save()
            if case .computingLocally = stateMachine.state { stateMachine.send(.reset) }
            return
        } catch {
            scan.computeStatusRaw = ScanComputeStatus.failed.rawValue
            try? modelContext.save()
            stateMachine.send(.errorOccurred(error.localizedDescription))
        }
    }

    private var optionStack: some View {
        VStack(spacing: 10) {
            ForEach(options) { opt in
                OptionCard(opt: opt, selected: sel == opt.id) { sel = opt.id }
            }
        }
    }
}

// MARK: - iPad layout (PadCompute — "Hub & spoke")

private struct PadComputeBody: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var model: StudioModel
    @EnvironmentObject private var stateMachine: ProcessingStateMachine
    @StateObject private var network = NetworkHandoffManager()
    @StateObject private var localCompute = ScanLocalComputeService()
    @Query(sort: \ScanSession.creationDate, order: .reverse) private var savedScans: [ScanSession]
    @State private var computeTask: Task<Void, Never>?
    @Binding var sel: String

    private var activeScan: ScanSession? {
        if let id = model.activeScanID, let scan = savedScans.first(where: { $0.id == id }) {
            return scan
        }
        return savedScans.first
    }

    private var isBusy: Bool {
        if computeTask != nil || localCompute.isRunning { return true }
        if case .computingOffloaded = stateMachine.state { return true }
        return false
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                PadComputeHeader(onCompute: startCompute)
                    .disabled(isBusy)
                PadHubCard(
                    sel: $sel,
                    peerName: network.connectedPeers.first?.displayName,
                    transferProgress: network.transferProgress,
                    scanSizeText: activeScan.map { "\($0.sizeMB) MB" } ?? "Pending",
                    requestedTier: activeScan?.tierRaw ?? model.selectedDetailTier
                )
                    .padding(.top, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(24)
        }
        .onAppear {
            network.onReceiveResultPackage = { url, _ in importResultPackage(url) }
            network.onSendError = { error in
                activeScan?.computeStatusRaw = ScanComputeStatus.failed.rawValue
                stateMachine.send(.errorOccurred("Mac handoff failed: \(error.localizedDescription)"))
            }
        }
        .onReceive(localCompute.$progress) { progress in
            guard localCompute.isRunning else { return }
            stateMachine.send(.updateLocalProgress(progress))
        }
        .onDisappear {
            computeTask?.cancel()
            computeTask = nil
            localCompute.cancel()
        }
    }

    private func startCompute(_ target: String) {
        guard !isBusy else { return }
        guard let activeScan else {
            stateMachine.send(.errorOccurred("No active scan is ready to compute."))
            return
        }

        if target == "mac" {
            guard let rawArchiveURL = activeScan.rawArchiveURL else {
                activeScan.computeStatusRaw = ScanComputeStatus.failed.rawValue
                stateMachine.send(.errorOccurred("Capture package is missing for Mac handoff."))
                return
            }
            let handoffArchive: URL
            do {
                handoffArchive = try ScanHandoffArchive.package(
                    rawArchiveURL,
                    captureQualityReport: activeScan.captureQualityReport
                )
            } catch {
                activeScan.computeStatusRaw = ScanComputeStatus.failed.rawValue
                stateMachine.send(.errorOccurred(error.localizedDescription))
                return
            }
            stateMachine.send(.userSelectsComputeMode(.offload))
            guard network.sendScanToFirstPeer(
                handoffArchive,
                metadata: ScanHandoffMetadata(
                    scanID: activeScan.id,
                    captureMode: activeScan.captureMode,
                    detailTier: activeScan.tierRaw
                )
            ) else {
                activeScan.computeStatusRaw = ScanComputeStatus.queued.rawValue
                stateMachine.send(.errorOccurred("No Mac is connected for handoff. Choose on-device compute or connect a Mac."))
                return
            }
            activeScan.computeStatusRaw = ScanComputeStatus.offloaded.rawValue
            stateMachine.send(.offloadToMac)
            stateMachine.send(.updateOffloadStatus("Sent \(handoffArchive.lastPathComponent) to Mac."))
        } else {
            activeScan.computeStatusRaw = ScanComputeStatus.local.rawValue
            stateMachine.send(.userSelectsComputeMode(.local))
            stateMachine.send(.startLocalCompute)
            computeTask = Task {
                await computeLocally(activeScan)
                computeTask = nil
            }
        }
    }

    private func computeLocally(_ scan: ScanSession) async {
        do {
            let output = try await localCompute.compute(scan: scan)
            try modelContext.save()
            stateMachine.send(.computeCompleted(output))
            model.go(.viewer)
        } catch is CancellationError {
            scan.computeStatusRaw = ScanComputeStatus.queued.rawValue
            try? modelContext.save()
            if case .computingLocally = stateMachine.state { stateMachine.send(.reset) }
            return
        } catch {
            scan.computeStatusRaw = ScanComputeStatus.failed.rawValue
            try? modelContext.save()
            stateMachine.send(.errorOccurred(error.localizedDescription))
        }
    }

    private func importResultPackage(_ packageURL: URL) {
        defer { network.removeReceivedResource(packageURL) }
        var importedScan: ScanSession?
        do {
            let fm = FileManager.default
            let importDirectory = fm.temporaryDirectory
                .appendingPathComponent("3dseen-result-import-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: importDirectory, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: importDirectory) }

            let result = try ScanResultPackage().unpack(packageURL, to: importDirectory)
            guard let targetScan = savedScans.first(where: { $0.id == result.manifest.scanID }) else {
                throw CocoaError(.fileReadUnknown)
            }
            importedScan = targetScan
            let store = try ScanAssetStore()
            let destination = try store.importCapture(from: result.modelURL, for: targetScan.id)
            let previewDestination = try result.previewPLYURL.map {
                try store.importCapture(from: $0, for: targetScan.id)
            }

            targetScan.markComputed(
                modelURL: destination,
                usdzURL: destination.pathExtension.lowercased() == "usdz" ? destination : nil,
                previewPLYURL: previewDestination,
                previewPLYKind: result.manifest.previewPLYKind
            )
            targetScan.captureModeRaw = result.manifest.captureMode.rawValue
            targetScan.tierRaw = result.manifest.detailTier
            targetScan.frameCount = max(targetScan.frameCount, result.manifest.frameCount)
            targetScan.coveragePercent = max(targetScan.coveragePercent, result.manifest.coveragePercent)
            targetScan.weakSpotCount = result.manifest.weakSpotCount
            if let report = result.manifest.captureQualityReport {
                targetScan.captureQualityReport = report
            }
            targetScan.triangles = ModelGeometryInspector.inspect(modelURL: destination)?.formattedTriangleCount ?? "Unavailable"
            try store.writeManifest(try store.manifest(for: targetScan))
            try modelContext.save()
            if model.activeScanID == targetScan.id {
                stateMachine.send(.computeCompleted(destination))
                model.go(.viewer)
            }
        } catch {
            importedScan?.computeStatusRaw = ScanComputeStatus.failed.rawValue
            stateMachine.send(.errorOccurred("The returned Mac result could not be matched to its source scan. \(error.localizedDescription)"))
        }
    }
}

private struct PadComputeHeader: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel
    @EnvironmentObject private var stateMachine: ProcessingStateMachine
    var onCompute: (String) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 12) {
                CircleIconButton(icon: "back", size: 38) { model.go(.review) }
                VStack(alignment: .leading, spacing: 2) {
                    StLabel(text: "Step 4 of 4 · Compute pipeline")
                    Text("Where should we render?")
                        .font(.sf(17, .bold)).tracking(0).foregroundStyle(theme.ink)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                StButton(title: "Compute on iPad · Reduced", kind: .secondary, size: .sm, icon: "chip") {
                    onCompute("local")
                }
                StButton(title: "Hand off to Mac", kind: .accent, size: .sm, icon: "laptop") {
                    onCompute("mac")
                }
            }
        }
    }
}

private struct PadHubCard: View {
    @Environment(\.theme) private var theme
    @Binding var sel: String
    let peerName: String?
    let transferProgress: Double
    let scanSizeText: String
    let requestedTier: String

    private var options: (mac: ComputeOption, local: ComputeOption) {
        ComputeOption.pair(theme, requestedTier: requestedTier)
    }

    var body: some View {
        StCard(radius: 26, pad: 28) {
            VStack(spacing: 0) {
                headerRow
                PadStreamingRow(peerName: peerName, transferProgress: transferProgress, scanSizeText: scanSizeText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                optionGrid
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                StLabel(text: "Hub & spoke", color: theme.accentText)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Capture here.").foregroundStyle(theme.ink)
                    Text("Render there.").foregroundStyle(theme.accentText)
                }
                .font(.sf(42, .heavy)).tracking(0)
                .padding(.top, 8)
                Text("Send the retained capture package to a connected Mac, or use RealityKit on this device.")
                    .font(.sf(14)).foregroundStyle(theme.text2).lineSpacing(6)
                    .frame(maxWidth: 430, alignment: .leading)
                    .padding(.top, 12)
            }
            Spacer(minLength: 16)
            PadConnectionCard(peerName: peerName)
        }
    }

    private var optionGrid: some View {
        HStack(spacing: 14) {
            OptionCard(opt: options.local, selected: sel == "local", big: true) { sel = "local" }
            OptionCard(opt: options.mac, selected: sel == "mac", big: true) { sel = "mac" }
        }
    }
}

private struct PadConnectionCard: View {
    @Environment(\.theme) private var theme
    let peerName: String?

    var body: some View {
        StCard(radius: 16, pad: 16, inset: true) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(peerName == nil ? theme.text3 : theme.good).frame(width: 9, height: 9).accessibilityHidden(true)
                    Text(peerName.map { "Connected to \($0)" } ?? "No Mac connected")
                        .font(.sf(13, .bold)).tracking(0).foregroundStyle(theme.ink)
                }
                Text(peerName == nil ? "Select on-device compute or connect a Mac." : "Available for secure local handoff.")
                    .font(.mono(10.5)).foregroundStyle(theme.text3).padding(.top, 4)
            }
        }
        .frame(width: 280)
    }
}

private struct PadStreamingRow: View {
    let peerName: String?
    let transferProgress: Double
    let scanSizeText: String

    var body: some View {
        HStack(spacing: 0) {
            PadDeviceTile(width: 180, height: 128, radius: 16, pad: 6, innerRadius: 10,
                          isMac: false, caption: "This device", sub: "CAPTURE · \(scanSizeText)")
            Spacer(minLength: 20)
            PadStreamCenter(progress: transferProgress, connected: peerName != nil).frame(maxWidth: 460)
            Spacer(minLength: 20)
            PadDeviceTile(width: 200, height: 128, radius: 9, pad: 5, innerRadius: 5,
                          isMac: true, caption: peerName ?? "Mac", sub: peerName == nil ? "NOT CONNECTED" : "CONNECTED")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 50)
    }
}

private struct PadStreamCenter: View {
    @Environment(\.theme) private var theme
    let progress: Double
    let connected: Bool

    var body: some View {
        VStack(spacing: 0) {
            StGlass(radius: 999) {
                HStack(spacing: 8) {
                    StIcon(name: "bolt", size: 13, color: theme.accent)
                    Text(connected ? "HANDOFF READY" : "AWAITING MAC").font(.mono(12, .bold)).foregroundStyle(theme.ink)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .fixedSize()
            .padding(.bottom, 8)

            HandoffArc(progress: progress).frame(height: 90).accessibilityHidden(true)

            HStack(spacing: 8) {
                PadMonoChip(text: "Encrypted")
                PadMonoChip(text: "Multipeer")
            }
            .padding(.top, 8)
        }
    }
}

private struct PadDeviceTile: View {
    @Environment(\.theme) private var theme
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
    var pad: CGFloat
    var innerRadius: CGFloat
    var isMac: Bool
    var caption: String
    var sub: String

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(theme.ink)
                .frame(width: width, height: height)
                .overlay(
                    Stage(radius: innerRadius) {
                        StIcon(name: isMac ? "laptop" : "tablet", size: 36, color: theme.text3)
                    }
                    .padding(pad)
                )
                .stShadow(theme.cardShadowLg)
                .accessibilityHidden(true)
            if isMac {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(theme.lineStrong)
                    .frame(width: 64, height: 5)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
            Text(caption)
                .font(.sf(14, .bold))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
                .padding(.top, isMac ? 9 : 10)
            StLabel(text: sub, color: theme.accentText)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
    }
}

/// Neutral monospace pill (Pad streaming chips: "AES-256", "multipeer", "ETA 0:38").
/// Bespoke because `StChip` is fixed to SF 12; the design specifies mono 10.5.
private struct PadMonoChip: View {
    @Environment(\.theme) private var theme
    var text: String

    var body: some View {
        Text(text)
            .font(.mono(10.5, .semibold))
            .foregroundStyle(theme.text2)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(theme.fieldFill))
            .overlay(Capsule().strokeBorder(theme.line, lineWidth: 0.5))
    }
}

// MARK: - Handoff arc (cobalt particle beam)

struct HandoffArc: View {
    @Environment(\.theme) private var theme
    var progress: Double = 0.58
    var dots: Int = 26

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let lift = h * 0.5
            let start = CGPoint(x: 10, y: h / 2)
            let end = CGPoint(x: w - 10, y: h / 2)
            let ctrl = CGPoint(x: w / 2, y: h / 2 - lift)
            var path = Path(); path.move(to: start); path.addQuadCurve(to: end, control: ctrl)
            ctx.stroke(path, with: .color(theme.line), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [2, 6]))
            for i in 0..<dots {
                let t = Double(i) / Double(dots - 1)
                let x = pow(1 - t, 2) * start.x + 2 * (1 - t) * t * ctrl.x + t * t * end.x
                let y = pow(1 - t, 2) * start.y + 2 * (1 - t) * t * ctrl.y + t * t * end.y
                let active = t <= progress
                let r = active ? 2.6 : 1.6
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(active ? theme.accent : theme.text3.opacity(0.5)))
            }
        }
    }
}

// MARK: - Device glyph (phone handoff card)

struct DeviceGlyph: View {
    enum Kind { case phone, mac }
    @Environment(\.theme) private var theme
    var kind: Kind
    var width: CGFloat
    var label: String
    var sub: String
    var subColor: Color

    var body: some View {
        VStack(spacing: 0) {
            let h = kind == .phone ? width * 1.6 : width * 0.64
            let r: CGFloat = kind == .phone ? 10 : 7
            RoundedRectangle(cornerRadius: r, style: .continuous).fill(theme.ink)
                .frame(width: width, height: h)
                .overlay(
                    Stage(radius: r - 3) {
                        StIcon(name: kind == .phone ? "phone" : "laptop", size: 24, color: theme.text3)
                    }
                    .padding(3)
                )
                .stShadow(theme.cardShadowLg)
                .accessibilityHidden(true)
            if kind == .mac {
                RoundedRectangle(cornerRadius: 1).fill(theme.lineStrong)
                    .frame(width: width * 1.18, height: 4)
                    .accessibilityHidden(true)
            }
            Text(label)
                .font(.sf(12.5, .semibold))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
                .padding(.top, kind == .mac ? 7 : 8)
            StLabel(text: sub, color: subColor)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
    }
}

// MARK: - Option card

/// "FASTEST" accent badge — bespoke 9px capsule (spec `<Chip style={{ fontSize: 9 }}>`),
/// since `StChip`/`StTextChip` are fixed at SF 12.
private struct FastestBadge: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("FASTEST")
            .font(.sf(9, .semibold))
            .tracking(0)
            .foregroundStyle(theme.accentText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(theme.accentSoft))
            .overlay(Capsule().strokeBorder(theme.accentLine, lineWidth: 0.5))
    }
}

struct OptionCard: View {
    @Environment(\.theme) private var theme
    let opt: ComputeOption
    var selected: Bool
    var big: Bool = false
    var onPick: () -> Void

    private var radius: CGFloat { big ? 20 : 18 }

    var body: some View {
        Button(action: onPick) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 11) {
                    iconTile
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(opt.name).font(.sf(16, .bold)).tracking(0).foregroundStyle(theme.ink)
                            if opt.best { FastestBadge() }
                        }
                        StLabel(text: opt.tag, color: selected ? theme.accentText : theme.text3)
                    }
                    Spacer(minLength: 0)
                }
                if !opt.stats.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(Array(opt.stats.enumerated()), id: \.offset) { _, s in
                            StStat(k: s.0, v: s.1, color: s.2, size: .sm)
                        }
                    }
                    .padding(.top, 14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(big ? 18 : 15)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(selected ? theme.accentSoft : theme.card))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(selected ? theme.accentLine : theme.line, lineWidth: selected ? 1 : 0.5))
            .stShadow(theme.cardShadow)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(selected ? theme.accent : theme.fieldFill)
            .frame(width: 38, height: 38)
            .overlay(StIcon(name: opt.icon, size: 20, color: selected ? theme.onAccent : theme.text2))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? .clear : theme.line, lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}
