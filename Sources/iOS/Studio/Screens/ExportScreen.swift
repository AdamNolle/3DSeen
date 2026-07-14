import SwiftUI
import SwiftData
import UIKit

/// The export screen only offers formats the bundled ModelIO pipeline can write. Sharing is
/// presented after a real file is written rather than pretending to target a named device/cloud.
struct ExportScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var model: StudioModel
    @Query(sort: \ScanSession.creationDate, order: .reverse) private var scans: [ScanSession]
    @State private var format: ExportFormat = .usdz
    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var exportedMeasurementURL: URL?
    @State private var errorMessage: String?
    @State private var showShareSheet = false
    @State private var exportTask: Task<Void, Never>?

    private var activeScan: ScanSession? {
        if let id = model.activeScanID, let scan = scans.first(where: { $0.id == id }) { return scan }
        return scans.first(where: \.hasRenderableAsset)
    }
    private var availableFormats: [ExportFormat] { ExportFormat.allCases.filter(\.isModelIONative) }
    private var canExport: Bool { activeScan?.hasRenderableAsset == true && !isExporting }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    preview
                    formatPicker
                    status
                    StButton(title: isExporting ? "Writing export…" : "Export \(format.rawValue)",
                             kind: .accent, size: .lg, icon: "export", full: true) { export() }
                        .disabled(!canExport)
                }
                .padding(20).padding(.bottom, 28)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportedURL { ShareSheet(items: shareItems(for: exportedURL)) }
        }
        .onDisappear {
            exportTask?.cancel()
            exportTask = nil
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CircleIconButton(icon: "back", size: 38) { model.go(.viewer) }
            VStack(alignment: .leading, spacing: 2) {
                StLabel(text: "Export")
                Text(activeScan?.name ?? "No computed scan")
                    .font(.sf(20, .bold))
                    .foregroundStyle(theme.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }
            Spacer()
        }
    }

    private var preview: some View {
        Stage(radius: 8) {
            VStack(spacing: 10) {
                Image(systemName: activeScan?.hasRenderableAsset == true ? "cube" : "cube.transparent")
                    .font(.system(size: 48, weight: .light)).foregroundStyle(theme.accentText)
                Text(activeScan?.displayModelURL?.lastPathComponent ?? "Compute a scan to export it")
                    .font(.mono(11))
                    .foregroundStyle(theme.text3)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .frame(height: 220)
    }

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            StLabel(text: "Format")
            ForEach(availableFormats, id: \.self) { candidate in
                Button { format = candidate } label: {
                    HStack(spacing: 12) {
                        Text(candidate.rawValue).font(.mono(12, .bold))
                            .foregroundStyle(candidate == format ? theme.onAccent : theme.ink)
                            .frame(width: 54, height: 34)
                            .background(RoundedRectangle(cornerRadius: 7).fill(candidate == format ? theme.accent : theme.fieldFill))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(description(for: candidate)).font(.sf(14, .semibold)).foregroundStyle(theme.ink)
                            Text(".\(candidate.fileExtension)").font(.mono(11)).foregroundStyle(theme.text3)
                        }
                        Spacer()
                        if candidate == format { StIcon(name: "check", size: 14, color: theme.accentText, weight: .heavy) }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(candidate == format ? theme.accentSoft : theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(candidate == format ? theme.accentLine : theme.line, lineWidth: candidate == format ? 1 : 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var status: some View {
        if isExporting {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("ModelIO is writing the selected format.").font(.sf(13)).foregroundStyle(theme.text2)
            }
        } else if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.sf(13)).foregroundStyle(theme.bad)
        } else if let exportedURL {
            HStack(spacing: 10) {
                Label(exportedMeasurementURL == nil
                      ? "Wrote \(exportedURL.lastPathComponent)"
                      : "Wrote model and measurements CSV", systemImage: "checkmark.circle")
                    .font(.sf(13)).foregroundStyle(theme.good)
                Spacer()
                StButton(title: "Share", kind: .secondary, size: .sm, icon: "share") { showShareSheet = true }
            }
        } else if activeScan?.hasRenderableAsset != true {
            Text("Compute the selected scan before exporting.").font(.sf(13)).foregroundStyle(theme.warn)
        }
    }

    private func description(for format: ExportFormat) -> String {
        switch format {
        case .usdz: return "Apple USDZ"
        case .usd: return "OpenUSD"
        case .obj: return "Wavefront OBJ"
        case .stl: return "STL mesh"
        case .ply: return "Polygon file"
        case .glb, .fbx: return "Unavailable"
        }
    }

    private func export() {
        guard let activeScan, let sourceModelURL = activeScan.displayModelURL else { return }
        isExporting = true
        exportedURL = nil
        exportedMeasurementURL = nil
        errorMessage = nil
        let selectedFormat = format
        let request = ModelExportRequest(
            scanID: activeScan.id,
            sourceModelURL: sourceModelURL,
            fileBaseName: activeScan.exportFileBaseName,
            measurements: activeScan.measurements
        )
        exportTask = Task {
            defer {
                isExporting = false
                exportTask = nil
            }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let output = try ModelExporter().export(request: request, to: selectedFormat)
                    let measurementOutput = request.measurements.isEmpty
                        ? nil
                        : try MeasurementExporter().exportCSV(
                            request.measurements,
                            named: request.fileBaseName,
                            to: output.deletingLastPathComponent()
                        )
                    return (output, measurementOutput)
                }.value
                try Task.checkCancellation()
                let assetStore = try ScanAssetStore()
                try ScanExportProvenanceRecorder.record(
                    result.0,
                    on: activeScan,
                    assetStore: assetStore
                ) {
                    try modelContext.save()
                }
                exportedURL = result.0
                exportedMeasurementURL = result.1
            } catch is CancellationError {
                errorMessage = "Export cancelled."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func shareItems(for modelURL: URL) -> [Any] {
        var items: [Any] = [modelURL]
        if let exportedMeasurementURL { items.append(exportedMeasurementURL) }
        return items
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
