// ViewerScreen.swift — finished 3D model viewer, ported from screens/viewer.jsx.
// Self-adapts on `horizontalSizeClass`: `.regular` → bespoke iPad layout (PadViewer),
// otherwise the immersive iPhone layout (PhoneViewer). Both float glass chrome over a
// full-bleed stage. Data is sourced from the selected persisted scan; an unavailable model is
// stated plainly instead of rendering a design sample as if it were capture output.

import QuickLook
import SwiftUI
import SwiftData
import RealityKit
import SceneKit
import UIKit

// MARK: - Material swatch model

struct MaterialSwatch: Identifiable {
    let id: String
    let label: String
    let g: (Color, Color)
}

enum USDZPresentationPolicy {
    static func eligibleURL(_ url: URL?) -> URL? {
        guard let url,
              url.pathExtension.lowercased() == "usdz",
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}

struct USDZQuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

let STUDIO_MATERIALS: [MaterialSwatch] = [
    .init(id: "pbr", label: "PBR", g: (Color(hex: "#BFA98C"), Color(hex: "#6B5C49"))),
    .init(id: "matte", label: "Matte", g: (Color(hex: "#E2D8C6"), Color(hex: "#8B7B62"))),
    .init(id: "metal", label: "Metal", g: (Color(hex: "#E8E6E2"), Color(hex: "#5A5E63"))),
    .init(id: "wire", label: "Wire", g: (Color(hex: "#9BC0FF"), Color(hex: "#2D68F0"))),
]

// MARK: - Adaptive root

struct ViewerScreen: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if hSize == .regular && !dynamicTypeSize.isAccessibilitySize {
            PadViewer()
        } else {
            PhoneViewer()
        }
    }
}

// MARK: - iPhone

private struct PhoneViewer: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var model: StudioModel
    @EnvironmentObject private var settings: SettingsStore
    @Query(sort: \ScanSession.creationDate, order: .reverse) private var savedScans: [ScanSession]
    @State private var mat = "pbr"
    @State private var tool = "orbit"
    @State private var showSplat = false
    @State private var showQuickLook = false
    @State private var pendingMeasurementPoint: ScanMeasurementPoint?

    private var activeScan: ScanSession? {
        if let id = model.activeScanID, let scan = savedScans.first(where: { $0.id == id }) {
            return scan
        }
        return savedScans.first
    }

    private var quickLookURL: URL? { USDZPresentationPolicy.eligibleURL(activeScan?.usdzFileURL) }
    private var displayName: String { activeScan?.name ?? "No Scan Selected" }
    private var triangleText: String { activeScan?.triangles ?? "—" }
    private var tierText: String { activeScan?.tierRaw ?? "—" }
    private var modeText: String { activeScan?.captureModeRaw ?? "—" }
    private var assetStatus: String {
        guard let activeScan else { return "NO SCAN SELECTED" }
        return activeScan.hasRenderableAsset ? "MODEL READY" : "AWAITING COMPUTE"
    }
    private var inspectorStatus: String {
        guard activeScan != nil else { return assetStatus }
        return "\(assetStatus) · \(modeText) · \(tierText)"
    }

    private var rail: [ToolRailItem] {
        [.init(id: "orbit", icon: "cube"),
         .init(id: "measure", icon: "ruler")]
    }

    var body: some View {
        ZStack {
            MeasuredAssetStage(
                assetURL: activeScan?.displayModelURL,
                measurements: activeScan?.measurements ?? [],
                pendingPoint: pendingMeasurementPoint,
                measurementEnabled: tool == "measure",
                materialStyle: mat,
                onPoint: addMeasurementPoint
            )
            .ignoresSafeArea()
            scrim
            if tool == "measure" { measurementUnavailableCallout }
            chrome
        }
        // This can be either a trained radiance field returned from a Mac or a clearly labeled
        // geometry-derived preview attached to the selected scan.
        .fullScreenCover(isPresented: $showSplat) {
            SplatViewerScreen(assetURL: activeScan?.previewPLYURL, onClose: { showSplat = false })
        }
        .sheet(isPresented: $showQuickLook) {
            if let quickLookURL { USDZQuickLookView(url: quickLookURL) }
        }
    }

    // Top/bottom legibility scrim over the light stage (spec layer 2).
    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.20), location: 0),
                .init(color: .clear, location: 0.26),
                .init(color: .clear, location: 0.72),
                .init(color: .black.opacity(0.24), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var measurementUnavailableCallout: some View {
        return MeasurePill(text: measurementPrompt)
            .padding(.top, 326).padding(.leading, 52)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private var measurementPrompt: String {
        if pendingMeasurementPoint != nil { return "Tap the second point" }
        if let measurement = activeScan?.measurements.last { return "\(measurementText(measurement)) · tap to add" }
        return "Tap the first point"
    }

    private func measurementText(_ measurement: ScanMeasurement) -> String {
        MeasurementFormatter.display(meters: measurement.meters, units: settings.units)
    }

    private func addMeasurementPoint(_ point: ScanMeasurementPoint) {
        guard let activeScan else { return }
        if let start = pendingMeasurementPoint {
            activeScan.measurements.append(ScanMeasurement(start: start, end: point, label: "Distance \(activeScan.measurements.count + 1)"))
            pendingMeasurementPoint = nil
            try? modelContext.save()
        } else {
            pendingMeasurementPoint = point
        }
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            topBar
            HStack {
                Spacer()
                ToolRail(items: rail, active: $tool)
            }
            .padding(.top, 12)
            Spacer()
            bottomInspector
            bottomActions.padding(.top, 8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 26)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button { model.go(.library) } label: {
                StIcon(name: "back", size: 18, color: theme.ink)
                    .frame(width: 38, height: 38).liquidGlass(radius: 999)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Library")

            StGlass(radius: 999) {
                Text(displayName)
                    .font(.sf(14, .bold)).tracking(0)
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9).padding(.horizontal, 14)
            }

            Button { model.go(.export) } label: {
                StIcon(name: "export", size: 18, color: theme.ink)
                    .frame(width: 38, height: 38).liquidGlass(radius: 999)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Export")
        }
    }

    private var bottomInspector: some View {
        StGlass(radius: 22) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    StLabel(text: inspectorStatus, color: activeScan?.hasRenderableAsset == true ? theme.good : theme.warn)
                    Spacer()
                    Text("v2").font(.mono(11)).foregroundStyle(theme.text3)
                }
                HStack(spacing: 8) {
                    StStat(k: "Tris", v: triangleText, size: .sm)
                    StStat(k: "Frames", v: activeScan.map { "\($0.frameCount)" } ?? "—", size: .sm)
                    StStat(k: "Measures", v: activeScan.map { "\($0.measurements.count)" } ?? "—", size: .sm)
                }
                .padding(.top, 12)
                MaterialPicker(value: $mat, compact: true).padding(.top, 12)
            }
            .padding(14)
        }
    }

    private var bottomActions: some View {
        GeometryReader { _ in
            HStack(spacing: 8) {
                StButton(title: "Splat", kind: .glass, icon: "scan", full: true) { showSplat = true }
                    .disabled(activeScan?.previewPLYURL == nil)
                StButton(title: "Quick Look / AR", kind: .glass, icon: "scan", full: true) {
                    showQuickLook = true
                }
                .disabled(quickLookURL == nil)
                .accessibilityHint("Opens Apple's USDZ preview with AR when this device supports it.")
                StButton(title: "Export", kind: .accent, icon: "export", full: true) { model.go(.export) }
            }
        }
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 56 : 44)
    }
}

// MARK: - iPad

private struct PadViewer: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var model: StudioModel
    @EnvironmentObject private var settings: SettingsStore
    @Query(sort: \ScanSession.creationDate, order: .reverse) private var savedScans: [ScanSession]
    @State private var mat = "pbr"
    @State private var tool = "orbit"
    @State private var showSplat = false
    @State private var showQuickLook = false
    @State private var pendingMeasurementPoint: ScanMeasurementPoint?

    private var activeScan: ScanSession? {
        if let id = model.activeScanID, let scan = savedScans.first(where: { $0.id == id }) {
            return scan
        }
        return savedScans.first
    }

    private var quickLookURL: URL? { USDZPresentationPolicy.eligibleURL(activeScan?.usdzFileURL) }
    private var displayName: String { activeScan?.name ?? "No Scan Selected" }
    private var triangleText: String { activeScan?.triangles ?? "—" }
    private var tierText: String { activeScan?.tierRaw.uppercased() ?? "—" }
    private var sizeText: String {
        guard let activeScan else { return "—" }
        return activeScan.sizeMB > 0 ? "\(activeScan.sizeMB) MB" : "pending"
    }

    private var rail: [ToolRailItem] {
        [.init(id: "orbit", icon: "cube", label: "Orbit"),
         .init(id: "measure", icon: "ruler", label: "Measure")]
    }

    var body: some View {
        ZStack {
            MeasuredAssetStage(
                assetURL: activeScan?.displayModelURL,
                measurements: activeScan?.measurements ?? [],
                pendingPoint: pendingMeasurementPoint,
                measurementEnabled: tool == "measure",
                materialStyle: mat,
                onPoint: addMeasurementPoint
            )
            .padding(.trailing, 362)
            .ignoresSafeArea()
            scrim
            if tool == "measure" { measurementUnavailableCallouts }
            topBar
            leftRail
            inspector
        }
        .fullScreenCover(isPresented: $showSplat) {
            SplatViewerScreen(assetURL: activeScan?.previewPLYURL, onClose: { showSplat = false })
        }
        .sheet(isPresented: $showQuickLook) {
            if let quickLookURL { USDZQuickLookView(url: quickLookURL) }
        }
    }

    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.16), location: 0),
                .init(color: .clear, location: 0.22),
                .init(color: .clear, location: 0.74),
                .init(color: .black.opacity(0.20), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var measurementUnavailableCallouts: some View {
        return ZStack(alignment: .topLeading) {
            MeasurePill(text: measurementPrompt)
                .padding(.top, 350).padding(.leading, 358)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var measurementPrompt: String {
        pendingMeasurementPoint == nil ? "Tap the first point" : "Tap the second point"
    }

    private func addMeasurementPoint(_ point: ScanMeasurementPoint) {
        guard let activeScan else { return }
        if let start = pendingMeasurementPoint {
            activeScan.measurements.append(ScanMeasurement(start: start, end: point, label: "Distance \(activeScan.measurements.count + 1)"))
            pendingMeasurementPoint = nil
            try? modelContext.save()
        } else {
            pendingMeasurementPoint = point
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { model.go(.library) } label: {
                StIcon(name: "back", size: 18, color: theme.ink)
                    .frame(width: 40, height: 40).liquidGlass(radius: 999)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Library")

            StGlass(radius: 999) {
                    Text(displayName)
                    .font(.sf(15, .bold)).tracking(0)
                    .foregroundStyle(theme.ink)
                    .padding(.vertical, 9).padding(.horizontal, 16)
            }
            StGlass(radius: 999) {
                    Text("\(tierText) · \(triangleText) · \(sizeText)")
                    .font(.mono(11)).foregroundStyle(theme.text2)
                    .padding(.vertical, 7).padding(.horizontal, 12)
            }
            Spacer()
            StButton(title: "Splat", kind: .glass, size: .sm, icon: "scan") { showSplat = true }
                .disabled(activeScan?.previewPLYURL == nil)
            StButton(title: "Quick Look / AR", kind: .glass, size: .sm, icon: "scan") {
                showQuickLook = true
            }
            .disabled(quickLookURL == nil)
            .accessibilityHint("Opens Apple's USDZ preview with AR when this device supports it.")
            StButton(title: "Export", kind: .accent, size: .sm, icon: "export") { model.go(.export) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 36).padding(.horizontal, 18)
    }

    private var leftRail: some View {
        ToolRail(items: rail, active: $tool, labels: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 96).padding(.leading, 18)
    }

    private var inspector: some View {
        VStack(spacing: 12) {
            geometryCard
            materialCard
            measurementsCard.frame(maxHeight: .infinity)
        }
        .frame(width: 326)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 96).padding(.trailing, 18).padding(.bottom, 18)
    }

    private var geometryCard: some View {
        StGlass(radius: 20) {
            VStack(alignment: .leading, spacing: 0) {
                StLabel(text: "Geometry", color: theme.accentText)
                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        StStat(k: "Triangles", v: triangleText, size: .sm)
                        StStat(k: "Frames", v: activeScan.map { "\($0.frameCount)" } ?? "—", size: .sm)
                    }
                    HStack(spacing: 14) {
                        StStat(k: "File", v: sizeText, size: .sm)
                        StStat(k: "Measures", v: activeScan.map { "\($0.measurements.count)" } ?? "—", size: .sm)
                    }
                }
                .padding(.top, 12)
            }
            .padding(16)
        }
    }

    private var materialCard: some View {
        StGlass(radius: 20) {
            VStack(alignment: .leading, spacing: 0) {
                StLabel(text: "Material override")
                MaterialPicker(value: $mat).padding(.top, 12)
            }
            .padding(16)
        }
    }

    private var measurementsCard: some View {
        StGlass(radius: 20) {
            VStack(alignment: .leading, spacing: 0) {
                StLabel(text: "Measurements", color: theme.good)
                if let measurements = activeScan?.measurements, !measurements.isEmpty {
                    ForEach(measurements) { measurement in
                        HStack {
                            Text(measurement.label).font(.sf(13.5)).foregroundStyle(theme.text2)
                            Spacer()
                            Text(measurementText(measurement)).font(.mono(12, .semibold)).foregroundStyle(theme.ink)
                        }
                        .padding(.top, 10)
                    }
                } else {
                    Text("Select Measure, then tap two model points.")
                        .font(.sf(13.5)).foregroundStyle(theme.text2)
                        .padding(.top, 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(16)
        }
    }

    private func measurementText(_ measurement: ScanMeasurement) -> String {
        MeasurementFormatter.display(meters: measurement.meters, units: settings.units)
    }

}

// MARK: - Measurement callout pill

private struct MeasuredAssetStage: View {
    let assetURL: URL?
    let measurements: [ScanMeasurement]
    let pendingPoint: ScanMeasurementPoint?
    let measurementEnabled: Bool
    let materialStyle: String
    let onPoint: (ScanMeasurementPoint) -> Void

    var body: some View {
        Stage {
            if let assetURL, FileManager.default.fileExists(atPath: assetURL.path) {
                SceneKitMeasurementView(
                    assetURL: assetURL,
                    measurements: measurements,
                    pendingPoint: pendingPoint,
                    measurementEnabled: measurementEnabled,
                    materialStyle: materialStyle,
                    onPoint: onPoint
                )
                .padding(28)
            } else {
                ContentUnavailableView(
                    assetURL == nil ? "No computed model" : "Unable to load model",
                    systemImage: assetURL == nil ? "cube" : "exclamationmark.triangle",
                    description: Text(assetURL == nil ? "Compute a scan to preview it here." : "The saved model could not be opened.")
                )
                .foregroundStyle(.secondary)
                .dynamicTypeSize(.medium ... .xxxLarge)
            }
        }
    }
}

/// SceneKit host with surface hit-testing for persistent point-to-point measurements.
private struct SceneKitMeasurementView: UIViewRepresentable {
    let assetURL: URL
    let measurements: [ScanMeasurement]
    let pendingPoint: ScanMeasurementPoint?
    let measurementEnabled: Bool
    let materialStyle: String
    let onPoint: (ScanMeasurementPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
        let recognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTap(_:)))
        view.addGestureRecognizer(recognizer)
        context.coordinator.view = view
        context.coordinator.load(assetURL)
        context.coordinator.update(measurements: measurements, pendingPoint: pendingPoint,
                                   measurementEnabled: measurementEnabled, materialStyle: materialStyle, onPoint: onPoint)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if context.coordinator.loadedURL != assetURL { context.coordinator.load(assetURL) }
        context.coordinator.update(measurements: measurements, pendingPoint: pendingPoint,
                                   measurementEnabled: measurementEnabled, materialStyle: materialStyle, onPoint: onPoint)
    }

    final class Coordinator: NSObject {
        weak var view: SCNView?
        var loadedURL: URL?
        private var materialStyle = "pbr"
        private var measurementEnabled = false
        private var onPoint: ((ScanMeasurementPoint) -> Void)?

        func load(_ url: URL) {
            view?.scene = try? SCNScene(url: url, options: nil)
            loadedURL = url
            applyMaterialStyle()
        }

        func update(measurements: [ScanMeasurement], pendingPoint: ScanMeasurementPoint?, measurementEnabled: Bool,
                    materialStyle: String, onPoint: @escaping (ScanMeasurementPoint) -> Void) {
            self.measurementEnabled = measurementEnabled
            self.onPoint = onPoint
            if self.materialStyle != materialStyle {
                self.materialStyle = materialStyle
                if let loadedURL { load(loadedURL) }
            }
            guard let root = view?.scene?.rootNode else { return }
            root.childNodes.filter { $0.name?.hasPrefix("3dseen-measurement-") == true }
                .forEach { $0.removeFromParentNode() }
            for measurement in measurements {
                addMarker(at: measurement.start, name: "3dseen-measurement-\(measurement.id)-start", color: .systemGreen, root: root)
                addMarker(at: measurement.end, name: "3dseen-measurement-\(measurement.id)-end", color: .systemGreen, root: root)
                addLine(from: measurement.start, to: measurement.end, name: "3dseen-measurement-\(measurement.id)-line", root: root)
            }
            if let pendingPoint {
                addMarker(at: pendingPoint, name: "3dseen-measurement-pending", color: .systemOrange, root: root)
            }
        }

        private func applyMaterialStyle() {
            guard let root = view?.scene?.rootNode else { return }
            root.enumerateChildNodes { node, _ in
                guard let geometry = node.geometry else { return }
                for material in geometry.materials {
                    switch self.materialStyle {
                    case "matte":
                        material.diffuse.contents = UIColor(white: 0.78, alpha: 1)
                        material.metalness.contents = 0
                        material.roughness.contents = 1
                        material.fillMode = .fill
                    case "metal":
                        material.diffuse.contents = UIColor(white: 0.72, alpha: 1)
                        material.metalness.contents = 1
                        material.roughness.contents = 0.22
                        material.fillMode = .fill
                    case "wire":
                        material.diffuse.contents = UIColor.systemBlue
                        material.metalness.contents = 0
                        material.roughness.contents = 0.5
                        material.fillMode = .lines
                    default:
                        material.fillMode = .fill
                    }
                }
            }
        }

        @objc func didTap(_ recognizer: UITapGestureRecognizer) {
            guard measurementEnabled, let view else { return }
            let location = recognizer.location(in: view)
            guard let result = view.hitTest(location, options: [.firstFoundOnly: true]).first else { return }
            let point = result.worldCoordinates
            onPoint?(ScanMeasurementPoint(x: Double(point.x), y: Double(point.y), z: Double(point.z)))
        }

        private func addMarker(at point: ScanMeasurementPoint, name: String, color: UIColor, root: SCNNode) {
            let sphere = SCNSphere(radius: 0.008)
            sphere.firstMaterial?.diffuse.contents = color
            sphere.firstMaterial?.emission.contents = color
            let node = SCNNode(geometry: sphere)
            node.name = name
            node.position = SCNVector3(point.x, point.y, point.z)
            root.addChildNode(node)
        }

        private func addLine(from start: ScanMeasurementPoint, to end: ScanMeasurementPoint, name: String, root: SCNNode) {
            let vertices = [SCNVector3(start.x, start.y, start.z), SCNVector3(end.x, end.y, end.z)]
            let source = SCNGeometrySource(vertices: vertices)
            let element = SCNGeometryElement(indices: [UInt32(0), UInt32(1)], primitiveType: .line)
            let geometry = SCNGeometry(sources: [source], elements: [element])
            geometry.firstMaterial?.diffuse.contents = UIColor.systemGreen
            geometry.firstMaterial?.emission.contents = UIColor.systemGreen
            let node = SCNNode(geometry: geometry)
            node.name = name
            root.addChildNode(node)
        }
    }
}

private struct MeasurePill: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        StGlass(radius: 10) {
            Text(text)
                .font(.mono(12, .bold))
                .foregroundStyle(theme.accentText)
                .padding(.vertical, 5).padding(.horizontal, 10)
        }
        .accessibilityLabel("Measurement \(text)")
    }
}

// MARK: - Tool rail

struct ToolRailItem: Identifiable {
    let id: String
    let icon: String
    var label: String = ""
}

struct ToolRail: View {
    @Environment(\.theme) private var theme
    var items: [ToolRailItem]
    @Binding var active: String
    var labels: Bool = false

    var body: some View {
        StGlass(radius: 18) {
            VStack(spacing: 4) {
                ForEach(items, id: \.id) { item in
                    railButton(item)
                }
            }
            .padding(6)
        }
        .fixedSize()
    }

    @ViewBuilder private func railButton(_ item: ToolRailItem) -> some View {
        let on = item.id == active
        Button { active = item.id } label: {
            VStack(spacing: 3) {
                StIcon(name: item.icon, size: 20, color: on ? theme.onAccent : theme.text2)
                if labels {
                    Text(item.label)
                        .font(.sf(9, .semibold))
                        .foregroundStyle(on ? theme.onAccent : theme.text3)
                }
            }
            .frame(width: 44, height: labels ? 50 : 44)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(on ? theme.accent : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label.isEmpty ? item.id.capitalized : item.label)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

// MARK: - Material picker (verbatim swatch control)

struct MaterialPicker: View {
    @Environment(\.theme) private var theme
    @Binding var value: String
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(STUDIO_MATERIALS) { m in
                let on = m.id == value
                Button { value = m.id } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(RadialGradient(colors: [m.g.0, m.g.1],
                                                 center: .init(x: 0.32, y: 0.28), startRadius: 0, endRadius: 22))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1).blendMode(.overlay))
                        Text(m.label).font(.sf(10.5, on ? .bold : .regular)).foregroundStyle(on ? theme.ink : theme.text3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 7 : 9).padding(.horizontal, compact ? 4 : 6)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? theme.fieldFillHi : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(on ? theme.accentLine : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(m.label)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
    }
}
