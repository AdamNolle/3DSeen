import SwiftUI
import SceneKit
import AppKit
import simd

/// Desktop viewer for the selected durable output. SceneKit provides the actual USDZ/PLY scene
/// and native mouse camera control; when no result exists the app says so instead of substituting
/// a concept model.
struct MacViewerPane: View {
    @Environment(\.theme) private var theme
    @Binding var section: MacSection
    @ObservedObject var compute: ComputeCoordinator
    @ObservedObject var settings: SettingsStore
    @State private var measurementEnabled = false
    @State private var pendingMeasurementPoint: ScanMeasurementPoint?
    @State private var measurementStatus = ""

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
            StButton(
                title: measurementEnabled ? "Stop measuring" : "Measure",
                kind: measurementEnabled ? .accent : .secondary,
                size: .sm,
                icon: "ruler"
            ) {
                measurementEnabled.toggle()
                pendingMeasurementPoint = nil
            }
            .disabled(scan == nil)
            .accessibilityHint("Select two points on the model to save their distance.")
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
            MacModelStage(
                assetURL: scan?.modelURL,
                measurements: scan?.manifest.measurements ?? [],
                measurementEnabled: measurementEnabled,
                onPoint: addMeasurementPoint
            )
            if scan != nil {
                StGlass(radius: 8) {
                    Label(
                        measurementEnabled
                            ? (pendingMeasurementPoint == nil ? "Click the first point" : "Click the second point")
                            : "Orbit with mouse drag",
                        systemImage: measurementEnabled ? "ruler" : "cursorarrow.motionlines"
                    )
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StLabel(text: "Measurements")
                Spacer()
                Button("Export CSV") { exportMeasurements() }
                    .buttonStyle(.link)
                    .disabled(scan?.manifest.measurements?.isEmpty != false)
            }
            if let values = scan?.manifest.measurements, !values.isEmpty {
                ForEach(values) { measurement in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(measurement.label).font(.sf(13, .semibold)).foregroundStyle(theme.ink)
                            Text(MeasurementFormatter.display(meters: measurement.meters, units: settings.units))
                                .font(.mono(11)).foregroundStyle(theme.text2)
                        }
                        Spacer()
                        Button(role: .destructive) { removeMeasurement(measurement) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete \(measurement.label)")
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("Choose Measure, then click two points on the model.")
                    .font(.sf(13)).foregroundStyle(theme.text3)
            }
            if !measurementStatus.isEmpty {
                Text(measurementStatus).font(.sf(12)).foregroundStyle(theme.text2)
            }
        }
    }

    private func addMeasurementPoint(_ point: ScanMeasurementPoint) {
        guard measurementEnabled, let scan else { return }
        guard let start = pendingMeasurementPoint else {
            pendingMeasurementPoint = point
            return
        }
        let count = (scan.manifest.measurements ?? []).count + 1
        let measurement = ScanMeasurement(start: start, end: point, label: "Distance \(count)")
        do {
            try compute.addMeasurement(measurement, to: scan.id)
            pendingMeasurementPoint = nil
            measurementStatus = "Saved \(measurement.label)."
        } catch {
            measurementStatus = "Could not save measurement: \(error.localizedDescription)"
        }
    }

    private func removeMeasurement(_ measurement: ScanMeasurement) {
        guard let scan else { return }
        do {
            try compute.removeMeasurement(measurement.id, from: scan.id)
            measurementStatus = "Deleted \(measurement.label)."
        } catch {
            measurementStatus = "Could not delete measurement: \(error.localizedDescription)"
        }
    }

    private func exportMeasurements() {
        guard let scan else { return }
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Exports/3DSeen", isDirectory: true)
        do {
            let url = try compute.exportMeasurements(for: scan.id, to: directory)
            measurementStatus = "Wrote \(url.lastPathComponent)."
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            measurementStatus = "Could not export measurements: \(error.localizedDescription)"
        }
    }
}

/// A truthful model stage shared by the macOS Library and Viewer. SceneKit can open USDZ and
/// common interchange formats available from the compute/export pipeline.
struct MacModelStage: View {
    @Environment(\.theme) private var theme
    let assetURL: URL?
    var measurements: [ScanMeasurement] = []
    var measurementEnabled = false
    var onPoint: ((ScanMeasurementPoint) -> Void)?

    var body: some View {
        Stage(radius: 8) {
            if let assetURL, FileManager.default.fileExists(atPath: assetURL.path) {
                MacScenePreview(
                    assetURL: assetURL,
                    measurements: measurements,
                    measurementEnabled: measurementEnabled,
                    onPoint: onPoint
                )
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
    let measurements: [ScanMeasurement]
    let measurementEnabled: Bool
    let onPoint: ((ScanMeasurementPoint) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
        view.rendersContinuously = false
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        view.addGestureRecognizer(click)
        context.coordinator.view = view
        context.coordinator.onPoint = onPoint
        context.coordinator.measurementEnabled = measurementEnabled
        load(assetURL, into: view, coordinator: context.coordinator)
        renderMeasurements(measurements, in: view)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.onPoint = onPoint
        context.coordinator.measurementEnabled = measurementEnabled
        if context.coordinator.loadedURL != assetURL {
            load(assetURL, into: view, coordinator: context.coordinator)
        }
        if context.coordinator.measurements != measurements {
            context.coordinator.measurements = measurements
            renderMeasurements(measurements, in: view)
        }
    }

    private func load(_ url: URL, into view: SCNView, coordinator: Coordinator) {
        view.scene = try? SCNScene(url: url, options: nil)
        coordinator.loadedURL = url
    }

    private func renderMeasurements(_ measurements: [ScanMeasurement], in view: SCNView) {
        guard let root = view.scene?.rootNode else { return }
        root.childNodes.filter { $0.name?.hasPrefix("3dseen-measurement-") == true }
            .forEach { $0.removeFromParentNode() }
        for measurement in measurements {
            let start = SIMD3<Float>(
                Float(measurement.start.x),
                Float(measurement.start.y),
                Float(measurement.start.z)
            )
            let end = SIMD3<Float>(
                Float(measurement.end.x),
                Float(measurement.end.y),
                Float(measurement.end.z)
            )
            let delta = end - start
            let length = simd_length(delta)
            guard length.isFinite, length > 0 else { continue }
            let line = SCNCylinder(radius: 0.0025, height: CGFloat(length))
            line.firstMaterial?.diffuse.contents = NSColor.systemOrange
            let node = SCNNode(geometry: line)
            node.name = "3dseen-measurement-\(measurement.id.uuidString)"
            node.simdPosition = (start + end) / 2
            node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
            root.addChildNode(node)
        }
    }

    final class Coordinator: NSObject {
        weak var view: SCNView?
        var loadedURL: URL?
        var measurements: [ScanMeasurement] = []
        var measurementEnabled = false
        var onPoint: ((ScanMeasurementPoint) -> Void)?

        @objc func handleClick(_ recognizer: NSClickGestureRecognizer) {
            guard measurementEnabled, let view else { return }
            let location = recognizer.location(in: view)
            guard let hit = view.hitTest(location).first else { return }
            let point = hit.worldCoordinates
            onPoint?(ScanMeasurementPoint(
                x: Double(point.x),
                y: Double(point.y),
                z: Double(point.z)
            ))
        }
    }
}
