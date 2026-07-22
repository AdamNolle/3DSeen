import SwiftUI
import SwiftData

/// Post-capture review. Capture engines currently retain frames and packaged assets, but do not
/// emit per-frame quality maps, so this screen reports those facts without drawing invented
/// coverage scores, rejected frames, or retake locations.
struct ReviewScreen: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
            PadReview()
        } else {
            PhoneReview()
        }
    }
}

private struct ReviewFacts {
    let scan: ScanSession?

    var frameCount: Int { scan?.frameCount ?? 0 }
    var isModelReady: Bool { scan?.hasRenderableAsset == true }
    var hasRawArchive: Bool { scan?.rawArchiveURL != nil }
    var canCompute: Bool { !isModelReady && hasRawArchive && scan?.captureStatus == .packaged }
    var canProceed: Bool { isModelReady || canCompute }
    var primaryTitle: String { isModelReady ? "View Model" : "Build Model" }
    var primaryIcon: String { isModelReady ? "cube" : "chip" }
    var mode: String { scan?.captureModeRaw ?? "Scan" }
    var archiveStatus: String { hasRawArchive ? "Ready" : "Missing" }
    var modelStatus: String { isModelReady ? "Ready" : "Pending" }
    var qualityReport: CaptureQualityReport? { scan?.captureQualityReport }
    var hasQualityWarnings: Bool { qualityReport?.warningCount ?? 0 > 0 }
}

private struct PhoneReview: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var model: StudioModel
    @Query(sort: \ScanSession.creationDate, order: .reverse) private var scans: [ScanSession]

    private var facts: ReviewFacts { ReviewFacts(scan: activeScan) }
    private var activeScan: ScanSession? {
        if let id = model.activeScanID, let scan = scans.first(where: { $0.id == id }) { return scan }
        return scans.first
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    title
                    captureCard
                    qualityNotice
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomCTA { actions }
        }
    }

    private var header: some View {
        HStack {
            CircleIconButton(icon: "back") { model.go(.mode) }
            Spacer()
            StChip(tone: facts.scan == nil ? .neutral : .good) {
                Circle().fill(facts.scan == nil ? theme.text3 : theme.good).frame(width: 6, height: 6)
                Text(facts.scan == nil ? "No capture selected" : "Capture retained")
            }
            Spacer()
            CircleIconButton(icon: "close") { model.go(.library) }
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            StLabel(text: "\(facts.mode) · \(facts.frameCount) saved photos")
            Text("Your scan is saved").font(.sf(28, .heavy)).foregroundStyle(theme.ink)
            Text("Review the photo check below. You can retake now or continue to build a model.")
                .font(.sf(13.5)).foregroundStyle(theme.text2)
        }
    }

    private var captureCard: some View {
        StCard(radius: 8, pad: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    StLabel(text: "Saved scan", color: theme.accentText)
                    Spacer()
                    StTextChip(text: facts.modelStatus.uppercased(), tone: facts.isModelReady ? .good : .neutral)
                }
                captureStats
                if let scan = facts.scan, let path = scan.displayModelURL ?? scan.rawArchiveURL {
                    Text(path.lastPathComponent).font(.mono(11)).foregroundStyle(theme.text3).lineLimit(1)
                }
            }
        }
    }

    private var qualityNotice: some View {
        StCard(radius: 8, pad: 18, inset: true) {
            if let report = facts.qualityReport {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        StIcon(name: facts.hasQualityWarnings ? "info" : "check", size: 18,
                               color: facts.hasQualityWarnings ? theme.warn : theme.good)
                        Text(report.summary).font(.sf(13, .semibold)).foregroundStyle(theme.ink)
                    }
                    qualityStats(report)
                    Text("This checks lighting and sharpness in sampled photos. It does not measure object coverage.")
                        .font(.sf(12)).foregroundStyle(theme.text3)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    StIcon(name: "info", size: 18, color: theme.accentText)
                    Text("This capture has no image-frame quality sample. Inspect the retained model or archive before continuing.")
                        .font(.sf(13)).foregroundStyle(theme.text2)
                }
            }
        }
    }

    private var actions: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) { actionButtons }
            } else {
                HStack(spacing: 8) { actionButtons }
            }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        StButton(title: "Retake", kind: .secondary, icon: "refresh", full: true) { model.go(.capture) }
        StButton(title: facts.primaryTitle, kind: .accent, icon: facts.primaryIcon, full: true) { proceed() }
            .disabled(!facts.canProceed)
    }

    @ViewBuilder private var captureStats: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: 14) {
                captureStatViews
            }
        } else {
            HStack(spacing: 18) { captureStatViews }
        }
    }

    @ViewBuilder private var captureStatViews: some View {
        StStat(k: "Frames", v: "\(facts.frameCount)", size: .sm)
        StStat(k: "Archive", v: facts.archiveStatus, color: facts.hasRawArchive ? theme.good : theme.warn, size: .sm)
        StStat(k: "Model", v: facts.modelStatus, color: facts.isModelReady ? theme.good : theme.text3, size: .sm)
    }

    @ViewBuilder private func qualityStats(_ report: CaptureQualityReport) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: 14) {
                qualityStatViews(report)
            }
        } else {
            HStack(spacing: 14) { qualityStatViews(report) }
        }
    }

    @ViewBuilder private func qualityStatViews(_ report: CaptureQualityReport) -> some View {
        StStat(k: "Sampled", v: "\(report.analyzedFrameCount)/\(report.totalFrameCount)", size: .sm)
        StStat(k: "Usable", v: "\(report.usablePercent)%", color: theme.good, size: .sm)
        if report.darkFrameCount > 0 { StStat(k: "Dark", v: "\(report.darkFrameCount)", color: theme.warn, size: .sm) }
        if report.brightFrameCount > 0 { StStat(k: "Bright", v: "\(report.brightFrameCount)", color: theme.warn, size: .sm) }
        if report.blurryFrameCount > 0 { StStat(k: "Soft", v: "\(report.blurryFrameCount)", color: theme.warn, size: .sm) }
    }

    private func proceed() {
        model.go(facts.isModelReady ? .viewer : .compute)
    }
}

private struct PadReview: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel
    @Query(sort: \ScanSession.creationDate, order: .reverse) private var scans: [ScanSession]

    private var facts: ReviewFacts { ReviewFacts(scan: activeScan) }
    private var activeScan: ScanSession? {
        if let id = model.activeScanID, let scan = scans.first(where: { $0.id == id }) { return scan }
        return scans.first
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                header
                StSplitPane(ratio: 0.56, gap: 16) { overview } right: { details }
            }
            .padding(24)
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 12) {
                CircleIconButton(icon: "back", size: 38) { model.go(.mode) }
                VStack(alignment: .leading, spacing: 2) {
                    StLabel(text: "Post-capture · \(facts.mode)", color: facts.scan == nil ? theme.text3 : theme.good)
                    Text("Review saved scan").font(.sf(17, .bold)).foregroundStyle(theme.ink)
                }
            }
            Spacer()
            StButton(title: "Retake", kind: .secondary, size: .sm, icon: "refresh") { model.go(.capture) }
            StButton(title: facts.primaryTitle, kind: .accent, size: .sm, icon: facts.primaryIcon) { proceed() }
                .disabled(!facts.canProceed)
        }
    }

    private var overview: some View {
        StCard(radius: 8, pad: 24) {
            VStack(alignment: .leading, spacing: 0) {
                StLabel(text: "Saved scan", color: theme.accentText)
                Text(facts.scan == nil ? "No scan selected" : "Ready to build")
                    .font(.sf(32, .heavy)).foregroundStyle(theme.ink).padding(.top, 8)
                Text(facts.isModelReady ? "Your model is ready to view and export." : "Build on this device, or use a connected Mac for the selected result quality.")
                    .font(.sf(14)).foregroundStyle(theme.text2).padding(.top, 8)
                Spacer()
                Image(systemName: facts.isModelReady ? "cube" : "archivebox")
                    .font(.system(size: 100, weight: .light)).foregroundStyle(theme.accentText)
                    .frame(maxWidth: .infinity)
                Spacer()
                StRule()
                HStack(spacing: 14) {
                    StStat(k: "Frames", v: "\(facts.frameCount)", size: .sm)
                    StStat(k: "Archive", v: facts.archiveStatus, color: facts.hasRawArchive ? theme.good : theme.warn, size: .sm)
                    StStat(k: "Model", v: facts.modelStatus, color: facts.isModelReady ? theme.good : theme.text3, size: .sm)
                }
                .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var details: some View {
        VStack(spacing: 14) {
            StCard(radius: 8, pad: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    StLabel(text: "Quality review")
                    if let report = facts.qualityReport {
                        Text(report.summary).font(.sf(18, .bold)).foregroundStyle(theme.ink)
                        Text(
                            "Sampled \(report.analyzedFrameCount) of \(report.totalFrameCount) retained frames: "
                                + "\(report.usableFrameCount) usable, \(report.darkFrameCount) dark, "
                                + "\(report.brightFrameCount) bright, \(report.blurryFrameCount) soft."
                        )
                            .font(.sf(13.5)).foregroundStyle(theme.text2)
                        Text("This checks lighting and sharpness only; object coverage still needs visual review.")
                            .font(.sf(12.5)).foregroundStyle(theme.text3)
                    } else {
                        Text("No image-frame quality sample").font(.sf(18, .bold)).foregroundStyle(theme.ink)
                        Text("This capture has no retained image frames to analyze. Inspect the model or archive before continuing.")
                            .font(.sf(13.5)).foregroundStyle(theme.text2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            StCard(radius: 8, pad: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    StLabel(text: "Asset path")
                    Text((facts.scan?.displayModelURL ?? facts.scan?.rawArchiveURL)?.path ?? "No capture asset")
                        .font(.mono(11)).foregroundStyle(theme.text3).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
    }

    private func proceed() {
        model.go(facts.isModelReady ? .viewer : .compute)
    }
}
