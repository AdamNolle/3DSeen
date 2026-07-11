import SwiftUI
import SceneKit
import AppKit

/// Desktop viewer for the selected durable output. SceneKit provides the actual USDZ/PLY scene
/// and native mouse camera control; when no result exists the app says so instead of substituting
/// a concept model.
struct MacViewerPane: View {
    @Environment(\.theme) private var theme
    @Binding var section: MacSection
    @ObservedObject var compute: ComputeCoordinator

    private var scan: MacComputedScan? { compute.selectedScan }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                stage
                StRule(vertical: true)
                inspector.frame(width: 320)
            }
        }
    }

    private var toolbar: some View {
        MacTopBar {
            MacBackButton(label: "Library") { section = .library }
            MacToolbarDivider()
            Circle().fill(scan == nil ? theme.text3 : theme.good).frame(width: 8, height: 8)
            Text(scan?.name ?? "No Scan Selected").font(.sf(15, .bold)).foregroundStyle(theme.ink).lineLimit(1)
            Text(modelSummary).font(.mono(12)).foregroundStyle(theme.text3).lineLimit(1)
            Spacer(minLength: 0)
            StButton(title: "Export…", kind: .accent, size: .sm, icon: "export") { section = .export }
                .disabled(scan == nil)
        }
    }

    private var modelSummary: String {
        guard let scan else { return "AWAITING COMPUTE" }
        return "\(scan.manifest.detailTier.uppercased()) · \(scan.sizeMB) MB"
    }

    private var stage: some View {
        ZStack(alignment: .topLeading) {
            MacModelStage(assetURL: scan?.modelURL)
            if scan != nil {
                StGlass(radius: 8) {
                    Label("Orbit with mouse drag", systemImage: "cursorarrow.motionlines")
                        .font(.sf(12, .medium)).foregroundStyle(theme.text2)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                }
                .padding(18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let scan {
                    geometry(scan)
                    StRule()
                    capture(scan)
                    StRule()
                    measurements
                } else {
                    ContentUnavailableView(
                        "No model selected",
                        systemImage: "cube",
                        description: Text("Open a completed scan from the library to inspect or export it.")
                    )
                    .padding(.top, 90)
                }
            }
            .padding(18)
        }
        .background(theme.card2)
    }

    private func geometry(_ scan: MacComputedScan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StLabel(text: "Model", color: theme.accentText)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                StStat(k: "Format", v: scan.modelURL.pathExtension.uppercased(), size: .sm)
                StStat(k: "File size", v: "\(scan.sizeMB) MB", size: .sm)
                StStat(k: "Detail", v: scan.manifest.detailTier, size: .sm)
                StStat(k: "Status", v: "Ready", color: theme.good, size: .sm)
            }
            Text(scan.modelURL.lastPathComponent).font(.mono(10)).foregroundStyle(theme.text3).textSelection(.enabled)
        }
    }

    private func capture(_ scan: MacComputedScan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StLabel(text: "Capture")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                StStat(k: "Mode", v: scan.manifest.captureMode.rawValue, size: .sm)
                StStat(k: "Frames", v: "\(scan.manifest.frameCount)", size: .sm)
                StStat(k: "Archive", v: scan.manifest.rawArchiveURL == nil ? "Missing" : "Saved", size: .sm)
                StStat(k: "Preview", v: scan.manifest.previewPLYURL == nil ? "None" : scan.manifest.previewPLYKind.rawValue, size: .sm)
            }
        }
    }

    private var measurements: some View {
        VStack(alignment: .leading, spacing: 8) {
            StLabel(text: "Measurements")
            Text("No measurements have been added to this scan.")
                .font(.sf(13)).foregroundStyle(theme.text3)
        }
    }
}

/// A truthful model stage shared by the macOS Library and Viewer. SceneKit can open USDZ and
/// common interchange formats available from the compute/export pipeline.
struct MacModelStage: View {
    @Environment(\.theme) private var theme
    let assetURL: URL?

    var body: some View {
        Stage(radius: 8) {
            if let assetURL, FileManager.default.fileExists(atPath: assetURL.path) {
                MacScenePreview(assetURL: assetURL)
            } else {
                ContentUnavailableView(
                    assetURL == nil ? "No computed model" : "Model unavailable",
                    systemImage: assetURL == nil ? "cube" : "exclamationmark.triangle",
                    description: Text(assetURL == nil
                                      ? "Complete a Mac handoff or local compute to preview a model."
                                      : "The retained model file can no longer be opened.")
                )
                .foregroundStyle(theme.text3)
            }
        }
    }
}

private struct MacScenePreview: NSViewRepresentable {
    let assetURL: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
        view.rendersContinuously = false
        load(assetURL, into: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        guard context.coordinator.loadedURL != assetURL else { return }
        load(assetURL, into: view, coordinator: context.coordinator)
    }

    private func load(_ url: URL, into view: SCNView, coordinator: Coordinator) {
        view.scene = try? SCNScene(url: url, options: nil)
        coordinator.loadedURL = url
    }

    final class Coordinator {
        var loadedURL: URL?
    }
}
