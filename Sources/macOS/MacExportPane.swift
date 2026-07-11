import SwiftUI
import AppKit

/// Exports the selected retained model. Choices are restricted to formats ModelIO can actually
/// write on this build; unavailable third-party conversion formats are not presented as actions.
struct MacExportPane: View {
    @Environment(\.theme) private var theme
    @Binding var section: MacSection
    @ObservedObject var compute: ComputeCoordinator
    @State private var format: ExportFormat = .usdz
    @State private var status = ""
    @State private var isExporting = false
    private let blenderConverter = BlenderModelConverter()

    private var scan: MacComputedScan? { compute.selectedScan }
    private var availableFormats: [ExportFormat] {
        ExportFormat.allCases.filter { $0.isModelIONative || blenderConverter.supports($0) && blenderConverter.isAvailable }
    }

    var body: some View {
        VStack(spacing: 0) {
            MacTopBar {
                MacBackButton(label: "Model") { section = .viewer }
                MacToolbarDivider()
                Text(scan.map { "Export · \($0.name)" } ?? "Export").font(.sf(15, .bold)).foregroundStyle(theme.ink).lineLimit(1)
                Spacer(minLength: 0)
                if let scan { StTextChip(text: "\(scan.sizeMB) MB SOURCE") }
            }
            HStack(spacing: 0) {
                preview.frame(maxWidth: .infinity)
                StRule(vertical: true)
                controls.frame(width: 390)
            }
        }
        .onChange(of: scan?.id) { _, _ in status = "" }
    }

    private var preview: some View {
        ZStack(alignment: .bottom) {
            MacModelStage(assetURL: scan?.modelURL)
            if let scan {
                StGlass(radius: 8) {
                    HStack(spacing: 22) {
                        StStat(k: "Source", v: scan.modelURL.pathExtension.uppercased(), size: .sm)
                        StStat(k: "Export", v: format.rawValue, size: .sm)
                        StStat(k: "Frames", v: "\(scan.manifest.frameCount)", size: .sm)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
                .padding(20)
            }
        }
        .padding(22)
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StLabel(text: "Format").padding(.bottom, 10)
                VStack(spacing: 8) {
                    ForEach(availableFormats, id: \.self) { candidate in
                        formatRow(candidate)
                    }
                }

                StRule().padding(.vertical, 20)
                StLabel(text: "Destination").padding(.bottom, 8)
                Text(destination.path(percentEncoded: false))
                    .font(.mono(11)).foregroundStyle(theme.text3).textSelection(.enabled)

                if !status.isEmpty {
                    Text(status).font(.sf(12.5)).foregroundStyle(theme.text2).padding(.top, 16)
                }
                StButton(title: isExporting ? "Writing export…" : "Export \(format.rawValue)", kind: .accent, size: .lg, icon: "export", full: true) { export() }
                    .padding(.top, 22)
                    .disabled(scan == nil || isExporting)
            }
            .padding(22)
        }
        .background(theme.card2)
    }

    private func formatRow(_ candidate: ExportFormat) -> some View {
        let selected = candidate == format
        return Button { format = candidate } label: {
            HStack(spacing: 12) {
                Text(candidate.rawValue).font(.mono(12, .bold)).foregroundStyle(selected ? theme.onAccent : theme.ink)
                    .frame(width: 52, height: 34)
                    .background(RoundedRectangle(cornerRadius: 7).fill(selected ? theme.accent : theme.fieldFill))
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatDescription(candidate)).font(.sf(13, .semibold)).foregroundStyle(theme.ink)
                    Text(".\(candidate.fileExtension)").font(.mono(11)).foregroundStyle(theme.text3)
                }
                Spacer()
                if selected { StIcon(name: "check", size: 14, color: theme.accentText, weight: .heavy) }
            }
            .padding(11)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? theme.accentSoft : theme.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? theme.accentLine : theme.line, lineWidth: selected ? 1 : 0.5))
        }
        .buttonStyle(.plain)
    }

    private var destination: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Exports/3DSeen", isDirectory: true)
    }

    private func formatDescription(_ format: ExportFormat) -> String {
        switch format {
        case .usdz: return "Apple USDZ"
        case .usd: return "OpenUSD"
        case .obj: return "Wavefront OBJ"
        case .stl: return "STL mesh"
        case .ply: return "Polygon file"
        case .glb: return "glTF binary · Blender"
        case .fbx: return "Autodesk FBX · Blender"
        }
    }

    private func export() {
        guard let scan else {
            status = "Select a computed scan before exporting."
            return
        }
        status = ""
        isExporting = true
        let selectedFormat = format
        let source = scan.modelURL
        let scanID = scan.id
        let scanName = scan.name
        let manifest = scan.manifest
        let converter = blenderConverter
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                let output: URL
                if selectedFormat.isModelIONative {
                    let session = ScanSession(
                        id: scanID,
                        captureMode: manifest.captureMode,
                        name: scanName,
                        tier: manifest.detailTier,
                        usdzFileURL: source.pathExtension.lowercased() == "usdz" ? source : nil,
                        sourceModelURL: source,
                        captureStatus: .captured,
                        computeStatus: .completed,
                        frameCount: manifest.frameCount,
                        coveragePercent: manifest.coveragePercent,
                        weakSpotCount: manifest.weakSpotCount
                    )
                    output = try ModelExporter().export(session: session, to: selectedFormat, outputDirectory: destination)
                } else {
                    let outputURL = destination
                        .appendingPathComponent(scanName.replacingOccurrences(of: "/", with: "-"))
                        .appendingPathExtension(selectedFormat.fileExtension)
                    output = try converter.convert(sourceURL: source, to: selectedFormat, outputURL: outputURL)
                }
                DispatchQueue.main.async {
                    status = "Wrote \(output.lastPathComponent)"
                    isExporting = false
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                }
            } catch {
                DispatchQueue.main.async {
                    status = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }
}
