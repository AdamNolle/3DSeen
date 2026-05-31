// QualityScreen.swift — detail / quality tier picker (iPhone), ported from screens/quality.jsx

import SwiftUI

struct DetailTier: Identifiable {
    let id: String
    let name: String
    let tag: String
    let tris: String
    let tex: String
    let size: String
    let time: String
    let use: String
    let psnr: Int
    var recommended: Bool = false
}

let DETAIL_TIERS: [DetailTier] = [
    .init(id: "preview", name: "Preview", tag: "Real-time draft", tris: "120k", tex: "512", size: "12 MB", time: "8 s", use: "Snap a quick reference", psnr: 22),
    .init(id: "reduced", name: "Reduced", tag: "Mobile-ready", tris: "480k", tex: "1024", size: "38 MB", time: "40 s", use: "AR Quick Look, web preview", psnr: 28),
    .init(id: "medium", name: "Medium", tag: "Most projects", tris: "1.2M", tex: "2048", size: "92 MB", time: "2:15", use: "Catalogs, light VFX, social", psnr: 33, recommended: true),
    .init(id: "full", name: "Full", tag: "Studio fidelity", tris: "4.2M", tex: "4096", size: "184 MB", time: "6:42", use: "Commercial, museum, PBR-correct", psnr: 38),
    .init(id: "raw", name: "Raw", tag: "Photogrammetric archive", tris: "16M+", tex: "8192", size: "1.1 GB", time: "21 min", use: "Re-process later · color-managed EXR", psnr: 44),
]

struct QualityScreen: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel
    @State private var sel = "medium"

    private var tier: DetailTier { DETAIL_TIERS.first { $0.id == sel } ?? DETAIL_TIERS[2] }

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WizardHeader(step: 3, onBack: { model.go(.briefing) }, onClose: { model.go(.library) })

                    VStack(alignment: .leading, spacing: 0) {
                        StLabel(text: "Detail tier")
                        Text("How much detail?").font(.sf(28, .heavy)).tracking(-0.9).foregroundStyle(theme.ink).padding(.top, 6)
                        Text("Matches Apple's PhotogrammetrySession tiers. Re-process anytime.")
                            .font(.sf(13.5)).foregroundStyle(theme.text2).padding(.top, 8)
                    }
                    .padding(.top, 18)

                    // scale selector
                    StCard(radius: 18, pad: 16) {
                        VStack(spacing: 0) {
                            HStack {
                                Text("FAST"); Spacer(); Text("BALANCED"); Spacer(); Text("ARCHIVE")
                            }
                            .font(.mono(10)).tracking(1).foregroundStyle(theme.text3)
                            .padding(.bottom, 12)
                            LinearGradient(colors: [theme.text4, theme.accent], startPoint: .leading, endPoint: .trailing)
                                .frame(height: 6).clipShape(Capsule())
                            HStack {
                                ForEach(DETAIL_TIERS) { t in
                                    let on = t.id == sel
                                    Button { sel = t.id } label: {
                                        VStack(spacing: 6) {
                                            Circle().fill(on ? theme.accent : theme.card)
                                                .frame(width: 13, height: 13)
                                                .overlay(Circle().strokeBorder(on ? theme.accent : theme.lineStrong, lineWidth: 2))
                                                .overlay(Circle().strokeBorder(theme.accentSoft, lineWidth: on ? 3 : 0))
                                                .offset(y: -10)
                                            Text(t.name.uppercased()).font(.mono(9.5, on ? .bold : .regular))
                                                .foregroundStyle(on ? theme.ink : theme.text3)
                                        }
                                    }.buttonStyle(.plain)
                                    if t.id != DETAIL_TIERS.last?.id { Spacer() }
                                }
                            }
                        }
                    }
                    .padding(.top, 14)

                    TierCard(tier: tier, selected: true, compact: false) {}.padding(.top, 14)

                    VStack(spacing: 8) {
                        ForEach(DETAIL_TIERS.filter { $0.id != sel }.prefix(2)) { t in
                            StCard(radius: 14, pad: 0) {
                                HStack(spacing: 12) {
                                    TierPreview(tier: t, size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.name).font(.sf(14, .semibold)).foregroundStyle(theme.ink)
                                        Text("\(t.tris) tris · \(t.size) · ~\(t.time)").font(.mono(10.5)).foregroundStyle(theme.text3)
                                    }
                                    Spacer(minLength: 0)
                                    StIcon(name: "chev", size: 15, color: theme.text3)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 12)
                            }
                            .onTapGesture { sel = t.id }
                        }
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
                .readableContentWidth()
            }

            BottomCTA {
                StButton(title: "Capture at \(tier.name)", kind: .accent, size: .lg, icon: "bolt", full: true) { model.go(.viewfinder) }
            }
        }
    }
}

struct TierPreview: View {
    @Environment(\.theme) private var theme
    let tier: DetailTier
    var size: CGFloat = 84

    private var segs: Int {
        ["preview": 6, "reduced": 10, "medium": 14, "full": 20, "raw": 28][tier.id] ?? 12
    }

    var body: some View {
        Stage(radius: 14) {
            Canvas { ctx, sz in
                let cx = sz.width / 2, cy = sz.height / 2
                let scale = sz.width / 100
                for i in 0..<segs {
                    let lat = (Double(i) / Double(segs) - 0.5) * .pi
                    let r = 32 * cos(lat) * scale
                    let ry = r * 0.34
                    let y = cy + 32 * sin(lat) * 0.6 * scale
                    ctx.stroke(Path(ellipseIn: CGRect(x: cx - r, y: y - ry, width: r * 2, height: ry * 2)),
                               with: .color(Stone.lo.opacity(0.3 + Double(i) / Double(segs) * 0.4)), lineWidth: 0.5)
                }
                let cr = 13 * scale
                ctx.fill(Path(ellipseIn: CGRect(x: cx - cr, y: cy - cr, width: cr * 2, height: cr * 2)), with: .color(Stone.mid.opacity(0.9)))
                let hr = 7 * scale
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 4 * scale - hr, y: cy - 4 * scale - hr, width: hr * 2, height: hr * 2)), with: .color(Stone.hi.opacity(0.8)))
            }
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.line, lineWidth: 0.5))
    }
}

struct TierCard: View {
    @Environment(\.theme) private var theme
    let tier: DetailTier
    var selected: Bool
    var compact: Bool
    var onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    TierPreview(tier: tier, size: compact ? 60 : 84)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Text(tier.name).font(.sf(compact ? 17 : 20, .bold)).tracking(-0.4).foregroundStyle(theme.ink)
                            if tier.recommended { StTextChip(text: "BEST", tone: .accent) } else if selected { StTextChip(text: "SELECTED", tone: .accent) }
                        }
                        StLabel(text: tier.tag, color: selected ? theme.accentText : theme.text3).padding(.top, 3)
                        if !compact {
                            Text(tier.use).font(.sf(13)).foregroundStyle(theme.text2).lineSpacing(1.5).padding(.top, 6)
                        }
                    }
                    Spacer(minLength: 0)
                }
                // stats row
                HStack(spacing: 0) {
                    statCell("Triangles", tier.tris, first: true)
                    statCell("Textures", tier.tex + "px")
                    statCell("Size", tier.size)
                    statCell("Compute", tier.time)
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { StRule() }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(compact ? 14 : 18)
            .background(RoundedRectangle(cornerRadius: compact ? 18 : 20, style: .continuous).fill(selected ? theme.accentSoft : theme.card))
            .overlay(RoundedRectangle(cornerRadius: compact ? 18 : 20, style: .continuous).strokeBorder(selected ? theme.accentLine : theme.line, lineWidth: selected ? 1 : 0.5))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func statCell(_ k: String, _ v: String, first: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            StLabel(text: k)
            Text(v).font(.sf(compact ? 13 : 15, .bold)).tracking(-0.2).monospacedDigit().foregroundStyle(theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, first ? 0 : 10)
        .overlay(alignment: .leading) { if !first { StRule(vertical: true) } }
    }
}
