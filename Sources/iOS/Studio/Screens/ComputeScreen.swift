// ComputeScreen.swift — compute pipeline & Mac handoff (iPhone), ported from screens/compute.jsx (PhoneCompute)

import SwiftUI

struct ComputeOption: Identifiable {
    let id: String
    let name: String
    let icon: String
    let tag: String
    var best: Bool = false
    let stats: [(String, String, Color?)]
}

struct ComputeScreen: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel
    @State private var sel = "mac"

    private var options: [ComputeOption] {
        [
            .init(id: "mac", name: "Mac handoff", icon: "laptop", tag: "M-series Neural Engine · no thermal cap", best: true,
                  stats: [("ETA", "1:52", theme.accentText), ("Speed", "3.6×", nil), ("Battery", "0%", theme.good), ("Quality", "Full", theme.good)]),
            .init(id: "local", name: "On-device", icon: "chip", tag: "RealityKit · auto-throttle · offline-ready",
                  stats: [("ETA", "6:42", nil), ("Speed", "1.0×", nil), ("Battery", "~22%", theme.warn), ("Throttle", "Auto", theme.good)]),
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WizardHeader(step: 4, onBack: { model.go(.review) }, onClose: { model.go(.library) })

                    VStack(alignment: .leading, spacing: 0) {
                        StLabel(text: "Where should we render?")
                        Text("Compute pipeline").font(.sf(28, .heavy)).tracking(-0.9).foregroundStyle(theme.ink).padding(.top, 6)
                        Text("Stay on iPhone, or hand off to your Mac on Wi-Fi.")
                            .font(.sf(13.5)).foregroundStyle(theme.text2).padding(.top, 8)
                    }
                    .padding(.top, 18)

                    // handoff card
                    StCard(radius: 22, pad: 20) {
                        HStack {
                            DeviceGlyph(kind: .phone, width: 46, label: "iPhone 16 Pro", sub: "SCAN · 1.1 GB", subColor: theme.accentText)
                            VStack(spacing: 2) {
                                HandoffArc(progress: 0.62).frame(height: 54)
                                Text("MULTIPEER · 1.2 Gbps").font(.mono(9.5)).tracking(1).foregroundStyle(theme.accentText)
                            }
                            .padding(.horizontal, 6)
                            DeviceGlyph(kind: .mac, width: 84, label: "MacBook Pro", sub: "M4 MAX", subColor: theme.text3)
                        }
                    }
                    .padding(.top, 14)

                    VStack(spacing: 10) {
                        ForEach(options) { opt in
                            OptionCard(opt: opt, selected: sel == opt.id) { sel = opt.id }
                        }
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
                .readableContentWidth()
            }

            BottomCTA {
                StButton(title: sel == "mac" ? "Hand off to MacBook Pro" : "Compute on iPhone",
                         kind: .accent, size: .lg, icon: sel == "mac" ? "laptop" : "chip", full: true) { model.go(.viewer) }
            }
        }
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

// MARK: - Device glyph

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
                    Stage(radius: r - 3) { HeroModel() }.padding(3)
                )
                .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
            if kind == .mac {
                RoundedRectangle(cornerRadius: 1).fill(theme.lineStrong)
                    .frame(width: width * 1.18, height: 4)
            }
            Text(label).font(.sf(12.5, .semibold)).foregroundStyle(theme.ink).padding(.top, kind == .mac ? 7 : 8)
            StLabel(text: sub, color: subColor).padding(.top, 2)
        }
    }
}

// MARK: - Option card

struct OptionCard: View {
    @Environment(\.theme) private var theme
    let opt: ComputeOption
    var selected: Bool
    var onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 11) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(selected ? theme.accent : theme.fieldFill)
                        .frame(width: 38, height: 38)
                        .overlay(StIcon(name: opt.icon, size: 20, color: selected ? theme.onAccent : theme.text2))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? .clear : theme.line, lineWidth: 0.5))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(opt.name).font(.sf(16, .bold)).tracking(-0.3).foregroundStyle(theme.ink)
                            if opt.best { StTextChip(text: "FASTEST", tone: .accent) }
                        }
                        StLabel(text: opt.tag, color: selected ? theme.accentText : theme.text3)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    ForEach(Array(opt.stats.enumerated()), id: \.offset) { _, s in
                        StStat(k: s.0, v: s.1, color: s.2, size: .sm)
                    }
                }
                .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(selected ? theme.accentSoft : theme.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? theme.accentLine : theme.line, lineWidth: selected ? 1 : 0.5))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 6)
        }
        .buttonStyle(.plain)
    }
}
