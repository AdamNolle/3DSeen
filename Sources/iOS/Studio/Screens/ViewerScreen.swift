// ViewerScreen.swift — finished 3D model viewer (iPhone), ported from screens/viewer.jsx (PhoneViewer)

import SwiftUI

struct MaterialSwatch: Identifiable {
    let id: String
    let label: String
    let g: (Color, Color)
}

let STUDIO_MATERIALS: [MaterialSwatch] = [
    .init(id: "pbr", label: "PBR", g: (Color(hex: "#BFA98C"), Color(hex: "#6B5C49"))),
    .init(id: "matte", label: "Matte", g: (Color(hex: "#E2D8C6"), Color(hex: "#8B7B62"))),
    .init(id: "metal", label: "Metal", g: (Color(hex: "#E8E6E2"), Color(hex: "#5A5E63"))),
    .init(id: "wire", label: "Wire", g: (Color(hex: "#9BC0FF"), Color(hex: "#2D68F0"))),
]

struct ViewerScreen: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel
    @State private var mat = "pbr"
    @State private var tool = "orbit"
    @State private var showSplat = false

    var body: some View {
        ZStack {
            Stage { HeroModel(material: mat) }.ignoresSafeArea()
            if tool == "measure" {
                MeasureOverlay(lines: [[158, 250, 158, 440]])
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // top bar
                HStack(spacing: 8) {
                    Button { model.go(.library) } label: {
                        StIcon(name: "back", size: 18, color: theme.ink)
                            .frame(width: 38, height: 38).liquidGlass(radius: 999)
                    }.buttonStyle(.plain)
                    StGlass(radius: 999) {
                        HStack(spacing: 8) {
                            Circle().fill(theme.good).frame(width: 7, height: 7)
                            Text("Celestial Bust").font(.sf(14, .semibold)).tracking(-0.2).foregroundStyle(theme.ink)
                            Text("· 4.2M · Full").font(.mono(11)).foregroundStyle(theme.text3)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14).frame(height: 38)
                    }
                    Button { model.go(.export) } label: {
                        StIcon(name: "export", size: 17, color: theme.ink)
                            .frame(width: 38, height: 38).liquidGlass(radius: 999)
                    }.buttonStyle(.plain)
                }

                // tool rail
                HStack {
                    Spacer()
                    ToolRail(items: [("orbit", "cube"), ("measure", "ruler"), ("pin", "pin"), ("splat", "sparkle"), ("light", "light")],
                             active: $tool)
                }
                .padding(.top, 12)

                Spacer()

                // bottom inspector
                StGlass(radius: 22) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            StLabel(text: "Captured today · Object · Full", color: theme.good)
                            Spacer()
                            Text("v2").font(.mono(11)).foregroundStyle(theme.text3)
                        }
                        HStack(spacing: 8) {
                            StStat(k: "Tris", v: "4.2M", size: .sm)
                            StStat(k: "Tex", v: "4K", size: .sm)
                            StStat(k: "PSNR", v: "38.7", size: .sm)
                            StStat(k: "Scale", v: "14cm", size: .sm)
                        }
                        .padding(.top, 12)
                        MaterialPicker(value: $mat, compact: true).padding(.top, 12)
                    }
                    .padding(14)
                }

                HStack(spacing: 8) {
                    StButton(title: "AR", kind: .glass, icon: "scan", full: true) {}
                    StButton(title: "Export", kind: .accent, icon: "export", full: true) { model.go(.export) }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 26)
        }
        .onChange(of: tool) { _, newValue in
            if newValue == "splat" { showSplat = true }
        }
        .fullScreenCover(isPresented: $showSplat, onDismiss: { tool = "orbit" }) {
            SplatViewerScreen(onClose: { showSplat = false })
        }
    }
}

// MARK: - Tool rail

struct ToolRail: View {
    @Environment(\.theme) private var theme
    var items: [(String, String)]   // (id, icon)
    @Binding var active: String

    var body: some View {
        StGlass(radius: 18) {
            VStack(spacing: 4) {
                ForEach(items, id: \.0) { id, icon in
                    let on = id == active
                    Button { active = id } label: {
                        StIcon(name: icon, size: 19, color: on ? theme.onAccent : theme.text2)
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(on ? theme.accent : .clear))
                    }.buttonStyle(.plain)
                }
            }
            .padding(6)
        }
        .fixedSize()
    }
}

// MARK: - Material picker

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
                            .fill(RadialGradient(colors: [m.g.0, m.g.1], center: .init(x: 0.32, y: 0.28), startRadius: 0, endRadius: 22))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1).blendMode(.overlay))
                        Text(m.label).font(.sf(10.5, on ? .bold : .regular)).foregroundStyle(on ? theme.ink : theme.text3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 7 : 9).padding(.horizontal, compact ? 4 : 6)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? theme.fieldFillHi : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? theme.accentLine : .clear, lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Measurement overlay

struct MeasureOverlay: View {
    @Environment(\.theme) private var theme
    /// lines in 402x874 design space: [x1,y1,x2,y2]
    var lines: [[CGFloat]]

    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 402, sy = size.height / 874
            for l in lines {
                var p = Path()
                p.move(to: CGPoint(x: l[0] * sx, y: l[1] * sy))
                p.addLine(to: CGPoint(x: l[2] * sx, y: l[3] * sy))
                ctx.stroke(p, with: .color(theme.accent), lineWidth: 1.4)
                for (px, py) in [(l[0], l[1]), (l[2], l[3])] {
                    ctx.fill(Path(ellipseIn: CGRect(x: px * sx - 3.4, y: py * sy - 3.4, width: 6.8, height: 6.8)), with: .color(theme.accent))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
