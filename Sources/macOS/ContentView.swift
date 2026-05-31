import SwiftUI
import AppKit

/// macOS "Studio" — a complete desktop app: browse the Library and drive the compute spoke
/// that renders hand-offs from iPhone. Reuses the shared Studio design system + render helpers.
struct ContentView: View {
    @StateObject private var compute = ComputeCoordinator()
    @State private var dark = false
    @State private var section: MacSection = .library

    private var theme: Theme { dark ? .dark : .light }

    var body: some View {
        MacShell(compute: compute, dark: $dark, section: $section)
            .environment(\.theme, theme)
            .preferredColorScheme(dark ? .dark : .light)
            .frame(minWidth: 1120, minHeight: 720)
    }
}

enum MacSection: String, CaseIterable {
    case library, viewer, compute, export
    var title: String {
        switch self {
        case .library: return "Library"
        case .viewer: return "Model"
        case .compute: return "Compute"
        case .export: return "Export"
        }
    }
    var icon: String {
        switch self {
        case .library: return "grid"
        case .viewer: return "cube"
        case .compute: return "chip"
        case .export: return "export"
        }
    }
}

private struct MacShell: View {
    @Environment(\.theme) private var theme
    @ObservedObject var compute: ComputeCoordinator
    @Binding var dark: Bool
    @Binding var section: MacSection

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 248)
            StRule(vertical: true)
            Group {
                switch section {
                case .library: MacLibraryPane(section: $section)
                case .viewer: MacViewerPane()
                case .compute: MacComputePane(compute: compute)
                case .export: MacExportPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.bg.ignoresSafeArea())
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.accent)
                    .frame(width: 30, height: 30)
                    .overlay(StIcon(name: "cube", size: 18, color: theme.onAccent, weight: .semibold))
                VStack(alignment: .leading, spacing: 0) {
                    Text("3DSeen").font(.sf(15, .bold)).tracking(-0.3).foregroundStyle(theme.ink)
                    Text("v2.4 · STUDIO").font(.mono(9.5)).foregroundStyle(theme.text3)
                }
            }
            .padding(.bottom, 12)

            ForEach(MacSection.allCases, id: \.self) { s in
                let on = s == section
                Button { section = s } label: {
                    HStack(spacing: 11) {
                        StIcon(name: s.icon, size: 17, color: on ? theme.accent : theme.text2)
                        Text(s.title).font(.sf(14, on ? .semibold : .regular)).foregroundStyle(on ? theme.ink : theme.text2)
                        Spacer()
                        if s == .compute, compute.isProcessing {
                            Circle().fill(theme.accent).frame(width: 7, height: 7)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? theme.fieldFillHi : .clear))
                }.buttonStyle(.plain)
            }

            Spacer()

            StCard(radius: 16, pad: 14, inset: true) {
                VStack(alignment: .leading, spacing: 8) {
                    StLabel(text: "Storage", color: theme.good)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("11.4").font(.sf(22, .bold)).tracking(-0.5).monospacedDigit().foregroundStyle(theme.ink)
                        Text("/ 256 GB").font(.sf(13)).foregroundStyle(theme.text3)
                    }
                    HStack(spacing: 2) {
                        Capsule().fill(theme.accent).frame(maxWidth: .infinity).frame(height: 5)
                        Capsule().fill(Color(hex: "#9B8769")).frame(width: 34, height: 5)
                        Capsule().fill(theme.warn).frame(width: 18, height: 5)
                    }
                }
            }
            Button { dark.toggle() } label: {
                HStack(spacing: 8) {
                    StIcon(name: dark ? "light" : "settings", size: 14, color: theme.text2)
                    Text(dark ? "Light appearance" : "Dark appearance").font(.sf(12.5)).foregroundStyle(theme.text2)
                    Spacer()
                }.padding(.vertical, 6)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 40) // clear traffic-light controls
        .padding(.bottom, 16)
        .background(theme.card2)
    }
}

// MARK: - Library pane

private struct MacLibraryPane: View {
    @Environment(\.theme) private var theme
    @Binding var section: MacSection

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("All Scans").font(.sf(15, .bold)).tracking(-0.3).foregroundStyle(theme.ink)
                StTextChip(text: "42 items")
                Spacer()
                StButton(title: "New Scan", kind: .accent, size: .sm, icon: "scan") {}
            }
            .padding(.horizontal, 20).frame(height: 52)
            .overlay(alignment: .bottom) { StRule() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // hero
                    StCard(radius: 22, pad: 22) {
                        HStack(spacing: 24) {
                            Stage(radius: 16) { HeroModel() }.frame(width: 220, height: 200)
                            VStack(alignment: .leading, spacing: 0) {
                                StLabel(text: "Just finished · Mac handoff complete", color: theme.accentText)
                                Text("Celestial Bust").font(.sf(34, .heavy)).tracking(-1).foregroundStyle(theme.ink).padding(.top, 8)
                                Text("Photogrammetry · 4.2M triangles · 8K PBR · 184 MB")
                                    .font(.sf(14)).foregroundStyle(theme.text2).padding(.top, 6)
                                HStack(spacing: 30) {
                                    macStat("Coverage", "99.4%", theme.good)
                                    macStat("Sharpness", "0.92", theme.ink)
                                    macStat("PSNR", "38.7 dB", theme.ink)
                                    macStat("Watertight", "Yes", theme.good)
                                }.padding(.top, 20)
                            }
                            Spacer(minLength: 0)
                            VStack(spacing: 8) {
                                StButton(title: "Open in 3D", kind: .accent, icon: "cube") { section = .viewer }
                                StButton(title: "Export…", kind: .secondary, icon: "export") { section = .export }
                                StButton(title: "Compute", kind: .ghost, icon: "chip") { section = .compute }
                            }
                        }
                    }
                    .padding(.bottom, 20)

                    Text("Recent").font(.sf(18, .bold)).tracking(-0.3).foregroundStyle(theme.ink).padding(.bottom, 14)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 5), spacing: 16) {
                        ForEach(SampleData.scans.dropFirst()) { s in ScanThumb(scan: s) }
                    }
                }
                .padding(24)
            }
        }
    }

    @ViewBuilder private func macStat(_ k: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            StLabel(text: k)
            Text(v).font(.sf(22, .bold)).tracking(-0.5).monospacedDigit().foregroundStyle(c)
        }
    }
}

// MARK: - Compute pane (pipeline · live preview · telemetry)

private struct MacComputePane: View {
    @Environment(\.theme) private var theme
    @ObservedObject var compute: ComputeCoordinator

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Circle().fill(theme.accent).frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(theme.accentSoft, lineWidth: 3))
                Text("Compute · Celestial Bust").font(.sf(15, .bold)).tracking(-0.3).foregroundStyle(theme.ink)
                StChip(tone: .accent) { StIcon(name: "laptop", size: 13, color: theme.accentText); Text("Handoff · \(compute.peerName)") }
                Spacer()
                StChip(tone: .neutral) { StIcon(name: "clock", size: 13, color: theme.text2); Text(etaText) }
                StButton(title: "Simulate hand-off", kind: .secondary, size: .sm, icon: "bolt") { compute.simulate() }
            }
            .padding(.horizontal, 20).frame(height: 52)
            .overlay(alignment: .bottom) { StRule() }

            HStack(spacing: 0) {
                pipelineRail.frame(width: 300)
                StRule(vertical: true)
                livePreview.frame(maxWidth: .infinity)
                StRule(vertical: true)
                telemetry.frame(width: 280)
            }
        }
    }

    private var etaText: String {
        switch compute.stage {
        case .done: return "Complete"
        case .waiting: return "Idle"
        default: return "\(Int((1 - compute.progress) * 112))s left"
        }
    }

    private var pipelineRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            StLabel(text: "Pipeline · RealityKit on Apple Silicon")
            VStack(alignment: .leading, spacing: 0) {
                let stages = ComputeCoordinator.Stage.allCases.filter { $0 != .waiting }
                ForEach(Array(stages.enumerated()), id: \.element) { i, s in
                    let done = compute.stage.rawValue > s.rawValue
                    let active = compute.stage == s && s != .done
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            ZStack {
                                Circle().fill(done ? theme.good : active ? theme.accentSoft : theme.fieldFill).frame(width: 26, height: 26)
                                if done {
                                    StIcon(name: "check", size: 14, color: .white, weight: .heavy)
                                } else if active {
                                    Circle().fill(theme.accent).frame(width: 8, height: 8)
                                } else {
                                    Text("\(i + 1)").font(.sf(11, .bold)).foregroundStyle(theme.text3)
                                }
                            }
                            if i < stages.count - 1 { Rectangle().fill(done ? theme.good : theme.line).frame(width: 2, height: 24) }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.label).font(.sf(14, .semibold)).foregroundStyle(active || done ? theme.ink : theme.text2)
                            if active { StMeter(value: compute.progress, color: theme.accent, height: 5).frame(width: 170).padding(.top, 6) }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.top, 16)
            Spacer()
        }
        .padding(20)
        .background(theme.card2)
    }

    private var livePreview: some View {
        ZStack {
            Stage { HeroModel(material: "wire") }
            VStack {
                HStack {
                    StChip(tone: .accent) {
                        Circle().fill(theme.accent).frame(width: 6, height: 6)
                        Text(compute.stage == .done ? "Render complete" : "\(compute.stage.label) · \(Int(compute.progress * 100))%")
                    }
                    Spacer()
                }
                Spacer()
                StGlass(radius: 16) {
                    HStack(spacing: 26) {
                        StStat(k: "Points", v: "3.1M", size: .sm)
                        StStat(k: "Frames", v: "\(compute.receivedFrames)", size: .sm)
                        StStat(k: "Confidence", v: "0.96", color: theme.good, size: .sm)
                        StStat(k: "Tris", v: "4.2M", size: .sm)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 12)
                }.fixedSize()
            }
            .padding(18)
        }
    }

    private var telemetry: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    StLabel(text: "Hardware")
                    bar("Neural Engine", compute.isProcessing ? 0.92 : 0.05, theme.accent, "38 TOPS")
                    bar("GPU · 40-core", compute.isProcessing ? 0.78 : 0.04, theme.accent, "76%")
                    bar("CPU · 16-core", compute.isProcessing ? 0.34 : 0.06, theme.text2, "34%")
                }
                StRule()
                VStack(alignment: .leading, spacing: 10) {
                    StLabel(text: "Transfer log")
                    if compute.log.isEmpty { Text("Waiting for hand-off…").font(.sf(12)).foregroundStyle(theme.text3) }
                    ForEach(Array(compute.log.suffix(7).enumerated()), id: \.offset) { _, e in
                        HStack(spacing: 10) {
                            Text(e.time).font(.mono(10.5)).foregroundStyle(theme.text4).frame(width: 56, alignment: .leading)
                            Text(e.message).font(.sf(12)).foregroundStyle(theme.text2); Spacer(minLength: 0)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .background(theme.card2)
    }

    @ViewBuilder private func bar(_ label: String, _ v: Double, _ c: Color, _ r: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(label).font(.sf(12.5, .semibold)).foregroundStyle(theme.ink); Spacer(); Text(r).font(.mono(11)).foregroundStyle(theme.text2) }
            StMeter(value: v, color: c, height: 5)
        }
    }
}

// MARK: - Viewer pane

private struct MacMaterial: Identifiable {
    let id: String
    let label: String
    let hi: Color
    let lo: Color
}

private let MAC_MATERIALS: [MacMaterial] = [
    .init(id: "pbr", label: "PBR", hi: Color(hex: "#BFA98C"), lo: Color(hex: "#6B5C49")),
    .init(id: "matte", label: "Matte", hi: Color(hex: "#E2D8C6"), lo: Color(hex: "#8B7B62")),
    .init(id: "metal", label: "Metal", hi: Color(hex: "#E8E6E2"), lo: Color(hex: "#5A5E63")),
    .init(id: "wire", label: "Wire", hi: Color(hex: "#9BC0FF"), lo: Color(hex: "#2D68F0"))
]

private struct MacViewerPane: View {
    @Environment(\.theme) private var theme
    @State private var mat = "pbr"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Circle().fill(theme.good).frame(width: 8, height: 8)
                Text("Celestial Bust").font(.sf(15, .bold)).tracking(-0.3).foregroundStyle(theme.ink)
                Text("FULL · 4.2M · 184 MB").font(.mono(12)).foregroundStyle(theme.text3)
                Spacer()
                StChip(tone: .neutral) { StIcon(name: "scan", size: 13, color: theme.text2); Text("AR Quick Look ready") }
            }
            .padding(.horizontal, 20).frame(height: 52)
            .overlay(alignment: .bottom) { StRule() }

            HStack(spacing: 0) {
                Stage { HeroModel(material: mat) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                StRule(vertical: true)
                inspector.frame(width: 320)
            }
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    StLabel(text: "Geometry", color: theme.accentText)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        StStat(k: "Triangles", v: "4.2M", size: .sm)
                        StStat(k: "Vertices", v: "2.1M", size: .sm)
                        StStat(k: "UV islands", v: "46", size: .sm)
                        StStat(k: "Watertight", v: "Yes", color: theme.good, size: .sm)
                    }
                }
                StRule()
                VStack(alignment: .leading, spacing: 12) {
                    StLabel(text: "Material override")
                    HStack(spacing: 6) {
                        ForEach(MAC_MATERIALS, id: \.id) { m in
                            let on = m.id == mat
                            Button { mat = m.id } label: {
                                VStack(spacing: 6) {
                                    Circle().fill(RadialGradient(colors: [m.hi, m.lo], center: .init(x: 0.32, y: 0.28), startRadius: 0, endRadius: 20))
                                        .frame(width: 28, height: 28)
                                    Text(m.label).font(.sf(10.5, on ? .bold : .regular)).foregroundStyle(on ? theme.ink : theme.text3)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 12).fill(on ? theme.fieldFillHi : .clear))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                StRule()
                VStack(alignment: .leading, spacing: 8) {
                    StLabel(text: "Measurements · 3 pins", color: theme.good)
                    ForEach(SampleData.measurements) { m in
                        HStack(spacing: 10) {
                            StTextChip(text: m.id, tone: .accent)
                            Text(m.label).font(.sf(13)).foregroundStyle(theme.text2)
                            Spacer(minLength: 0)
                            Text("\(m.value) \(m.unit)").font(.sf(14, .bold)).monospacedDigit().foregroundStyle(theme.ink)
                        }
                        .padding(.vertical, 4)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .background(theme.card2)
    }
}

// MARK: - Export pane (writes a real file + reveals in Finder)

private struct MacExportPane: View {
    @Environment(\.theme) private var theme
    @State private var fmt = "usdz"
    @State private var status = ""

    private var engineFormat: ExportFormat {
        switch fmt {
        case "usd": return .usd
        case "glb": return .glb
        case "obj": return .obj
        case "fbx": return .fbx
        case "ply": return .ply
        default: return .usdz
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("Export · Celestial Bust").font(.sf(15, .bold)).tracking(-0.3).foregroundStyle(theme.ink)
                Spacer()
                StChip(tone: .neutral) { StIcon(name: "layers", size: 13, color: theme.text2); Text("\(SampleData.exportFormats.count) formats") }
            }
            .padding(.horizontal, 20).frame(height: 52)
            .overlay(alignment: .bottom) { StRule() }

            HStack(spacing: 0) {
                ZStack {
                    Stage { HeroModel(material: fmt == "ply" ? "wire" : "pbr") }
                    VStack {
                        HStack { StChip(tone: .accent) { StIcon(name: "scan", size: 13, color: theme.accentText); Text("AR Quick Look ready") }; Spacer() }
                        Spacer()
                    }.padding(18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                StRule(vertical: true)
                config.frame(width: 380)
            }
        }
    }

    private var config: some View {
        VStack(alignment: .leading, spacing: 0) {
            StLabel(text: "Format")
            VStack(spacing: 8) {
                ForEach(SampleData.exportFormats) { f in
                    let on = f.id == fmt
                    Button { fmt = f.id } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 10).fill(on ? theme.accent : theme.card)
                                .frame(width: 40, height: 40)
                                .overlay(Text(f.name).font(.sf(11.5, .heavy)).foregroundStyle(on ? theme.onAccent : theme.text2))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? .clear : theme.line, lineWidth: 0.5))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.ext).font(.mono(13, .semibold)).foregroundStyle(theme.ink)
                                Text(f.desc).font(.sf(11.5)).foregroundStyle(theme.text3)
                            }
                            Spacer(minLength: 0)
                            Text(f.size).font(.mono(12)).foregroundStyle(theme.text2)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(on ? theme.accentSoft : theme.fieldFill))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(on ? theme.accentLine : theme.line, lineWidth: on ? 1 : 0.5))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.top, 10)

            Spacer(minLength: 0)
            if !status.isEmpty {
                Text(status).font(.mono(11)).foregroundStyle(theme.text3).padding(.bottom, 8)
            }
            StButton(title: "Export \(engineFormat.rawValue)", kind: .accent, size: .lg, icon: "export", full: true) { export() }
        }
        .padding(20)
        .background(theme.card2)
    }

    private func export() {
        do {
            let out = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?
                .appendingPathComponent("celestial-bust").appendingPathExtension(engineFormat.fileExtension)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("celestial-bust").appendingPathExtension(engineFormat.fileExtension)
            let exporter = ModelExporter()
            try exporter.export(asset: exporter.sampleAsset(), to: engineFormat, outputURL: out)
            status = "Wrote \(out.lastPathComponent) → Downloads"
            NSWorkspace.shared.activateFileViewerSelecting([out])
        } catch {
            status = error.localizedDescription
        }
    }
}

#Preview { ContentView() }
