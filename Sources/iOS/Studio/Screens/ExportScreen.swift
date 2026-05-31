// ExportScreen.swift — file output flow: config → progress → done (iPhone bottom sheet),
// ported from screens/export.jsx (PhoneExport). This is the "modal/screen for outputting files".

import SwiftUI
import UIKit

struct ExportDestination: Identifiable {
    let id: String
    let label: String
    let icon: String
}

let EXPORT_DESTINATIONS: [ExportDestination] = [
    .init(id: "air", label: "AirDrop", icon: "airdrop"),
    .init(id: "mac", label: "Adam's MBP", icon: "laptop"),
    .init(id: "icloud", label: "iCloud", icon: "cloud"),
    .init(id: "files", label: "Files", icon: "folder"),
]

private let EXPORT_OPTIONS: [(String, String, Bool)] = [
    ("measure", "Include measurements (3 pins)", true),
    ("bake", "Bake materials to 2K", false),
    ("scale", "Scale to scene · 1.0×", true),
    ("color", "Color-managed (Display P3)", true),
]

final class ExportFlow: ObservableObject {
    enum Stage { case config, progress, done }
    @Published var stage: Stage = .config
    @Published var fmt = "usdz"
    @Published var dest = "air"
    @Published var pct: Double = 0
    @Published var opts: [String: Bool] = Dictionary(uniqueKeysWithValues: EXPORT_OPTIONS.map { ($0.0, $0.2) })
    /// The real file written by ModelExporter, ready to share.
    @Published var exportedURL: URL?
    @Published var exportError: String?
    private var timer: Timer?

    var format: ExportFormatInfo { SampleData.exportFormats.first { $0.id == fmt } ?? SampleData.exportFormats[0] }

    /// Map the UI format id to the engine's ExportFormat.
    private var engineFormat: ExportFormat {
        switch fmt {
        case "usd": return .usd
        case "glb": return .glb
        case "obj": return .obj
        case "fbx": return .fbx
        case "ply": return .ply
        default:    return .usdz
        }
    }

    func start() {
        stage = .progress; pct = 0; exportedURL = nil; exportError = nil
        // Real export off the main thread (writes an actual file via ModelIO).
        let format = engineFormat
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let url = try ModelExporter().exportSample(to: format)
                DispatchQueue.main.async { self.exportedURL = url }
            } catch {
                DispatchQueue.main.async { self.exportError = error.localizedDescription }
            }
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] t in
            guard let self else { return }
            let np = self.pct + Double.random(in: 3...12)
            if np >= 100 {
                self.pct = 100; t.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                    self.stage = .done
                    Haptics.success()
                }
            } else {
                self.pct = np
            }
        }
    }
    func reset() { timer?.invalidate(); stage = .config; pct = 0; exportedURL = nil; exportError = nil }
    deinit { timer?.invalidate() }
}

/// UIKit share sheet for the exported file.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ExportScreen: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel
    @StateObject private var flow = ExportFlow()

    var body: some View {
        ZStack(alignment: .bottom) {
            Stage { HeroModel() }.ignoresSafeArea()
            (theme.mode == .dark ? Color.black.opacity(0.45) : Color(.sRGB, red: 20/255, green: 20/255, blue: 30/255, opacity: 0.28))
                .ignoresSafeArea()

            // sheet
            StGlass(radius: 30) {
                VStack(spacing: 0) {
                    Capsule().fill(theme.lineStrong).frame(width: 38, height: 5).padding(.bottom, 14)
                    switch flow.stage {
                    case .config:   configView
                    case .progress: ProgressView(pct: flow.pct, format: flow.format, dest: flow.dest)
                    case .done:     DoneView(format: flow.format, dest: flow.dest, exportedURL: flow.exportedURL, error: flow.exportError, onAgain: { flow.reset() }, onDone: { model.go(.library) })
                    }
                }
                .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 34)
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30))
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var configView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ModelBadge()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Celestial Bust").font(.sf(17, .bold)).tracking(-0.3).foregroundStyle(theme.ink)
                    Text("FULL · 4.2M tris · 184 MB").font(.mono(11)).foregroundStyle(theme.text3)
                }
                Spacer(minLength: 0)
                Button { model.go(.viewer) } label: {
                    StIcon(name: "close", size: 15, color: theme.text2).frame(width: 32, height: 32).background(Circle().fill(theme.fieldFill))
                }.buttonStyle(.plain)
            }

            StLabel(text: "Send to").padding(.top, 18).padding(.bottom, 10)
            DestRow(value: $flow.dest)

            StLabel(text: "Format").padding(.top, 18).padding(.bottom, 10)
            VStack(spacing: 8) {
                ForEach(SampleData.exportFormats.prefix(3)) { f in
                    FormatRow(f: f, on: flow.fmt == f.id) { flow.fmt = f.id }
                }
            }

            VStack(spacing: 2) {
                ForEach(EXPORT_OPTIONS.prefix(2), id: \.0) { key, label, _ in
                    HStack {
                        Text(label).font(.sf(13.5, .medium)).foregroundStyle(theme.ink)
                        Spacer()
                        StToggle(on: Binding(get: { flow.opts[key] ?? false }, set: { flow.opts[key] = $0 }))
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.top, 14)

            StButton(title: "Export \(flow.format.name) · \(flow.format.size)", kind: .accent, size: .lg, icon: "export", full: true) { flow.start() }
                .padding(.top, 16)
        }
    }
}

// MARK: - Pieces

struct ModelBadge: View {
    @Environment(\.theme) private var theme
    var size: CGFloat = 50
    var body: some View {
        Stage(radius: 12) { HeroModel() }
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.line, lineWidth: 0.5))
    }
}

struct FormatRow: View {
    @Environment(\.theme) private var theme
    let f: ExportFormatInfo
    var on: Bool
    var onPick: () -> Void
    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? theme.accent : theme.card)
                    .frame(width: 40, height: 40)
                    .overlay(Text(f.name).font(.sf(11.5, .heavy)).tracking(-0.2).foregroundStyle(on ? theme.onAccent : theme.text2))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? .clear : theme.line, lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(f.ext).font(.mono(14, .semibold)).foregroundStyle(theme.ink)
                        if f.best { StTextChip(text: "BEST", tone: .accent) }
                    }
                    Text(f.desc).font(.sf(11.5)).foregroundStyle(theme.text3)
                }
                Spacer(minLength: 0)
                Text(f.size).font(.mono(12)).foregroundStyle(theme.text2)
                ZStack {
                    Circle().fill(on ? theme.accent : .clear).frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(on ? .clear : theme.line, lineWidth: 1.5))
                    if on { StIcon(name: "check", size: 13, color: theme.onAccent, weight: .heavy) }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? theme.accentSoft : theme.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? theme.accentLine : theme.line, lineWidth: on ? 1 : 0.5))
        }.buttonStyle(.plain)
    }
}

struct DestRow: View {
    @Environment(\.theme) private var theme
    @Binding var value: String
    var body: some View {
        HStack(spacing: 12) {
            ForEach(EXPORT_DESTINATIONS) { d in
                let on = d.id == value
                Button { value = d.id } label: {
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? theme.accent : theme.fieldFill)
                            .frame(width: 56, height: 56)
                            .overlay(StIcon(name: d.icon, size: 24, color: on ? theme.onAccent : theme.text2))
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(on ? .clear : theme.line, lineWidth: 0.5))
                        Text(d.label).font(.sf(11.5, on ? .semibold : .regular)).foregroundStyle(on ? theme.ink : theme.text2)
                    }
                    .frame(maxWidth: .infinity)
                }.buttonStyle(.plain)
            }
        }
    }
}

private struct ProgressView: View {
    @Environment(\.theme) private var theme
    var pct: Double
    var format: ExportFormatInfo
    var dest: String
    var body: some View {
        let d = EXPORT_DESTINATIONS.first { $0.id == dest } ?? EXPORT_DESTINATIONS[0]
        VStack(spacing: 16) {
            StRing(value: pct / 100, size: 104, stroke: 8, label: "\(Int(pct))", sub: "%")
            VStack(spacing: 4) {
                Text("Exporting \(format.name)…").font(.sf(16, .bold)).tracking(-0.3).foregroundStyle(theme.ink)
                Text("\(pct < 40 ? "Triangulating mesh" : pct < 75 ? "Packing 4K textures" : "Writing \(format.ext)") · \(format.size)")
                    .font(.sf(13)).foregroundStyle(theme.text2)
            }
            StChip(tone: .neutral) { StIcon(name: d.icon, size: 14, color: theme.text2); Text("to \(d.label)") }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}

private struct DoneView: View {
    @Environment(\.theme) private var theme
    var format: ExportFormatInfo
    var dest: String
    var exportedURL: URL?
    var error: String?
    var onAgain: () -> Void
    var onDone: () -> Void
    @State private var showShare = false

    var body: some View {
        let d = EXPORT_DESTINATIONS.first { $0.id == dest } ?? EXPORT_DESTINATIONS[0]
        VStack(spacing: 14) {
            Circle().fill(theme.goodSoft).frame(width: 68, height: 68)
                .overlay(Circle().fill(theme.good).frame(width: 46, height: 46)
                    .overlay(StIcon(name: "check", size: 24, color: .white, weight: .heavy)))
            VStack(spacing: 5) {
                Text("Export complete").font(.sf(18, .heavy)).tracking(-0.4).foregroundStyle(theme.ink)
                if let url = exportedURL {
                    Text("\(url.lastPathComponent) written · sent to \(d.label)")
                        .font(.sf(13.5)).foregroundStyle(theme.text2).multilineTextAlignment(.center)
                } else if let error {
                    Text(error).font(.sf(12.5)).foregroundStyle(theme.warn).multilineTextAlignment(.center)
                } else {
                    Text("Celestial Bust\(format.ext) · \(format.size) · sent to \(d.label)")
                        .font(.sf(13.5)).foregroundStyle(theme.text2).multilineTextAlignment(.center)
                }
            }
            HStack(spacing: 8) {
                if exportedURL != nil {
                    StButton(title: "Share file", kind: .secondary, icon: "share") { showShare = true }
                } else {
                    StButton(title: "Export again", kind: .secondary, icon: "refresh", action: onAgain)
                }
                StButton(title: "Done", kind: .accent, icon: "check", action: onDone)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showShare) {
            if let url = exportedURL { ShareSheet(items: [url]) }
        }
    }
}
