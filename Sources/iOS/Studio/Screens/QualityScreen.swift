// QualityScreen.swift — detail / quality tier picker, ported from screens/quality.jsx.
// Self-adapting: compact (iPhone) renders the scrolling `PhoneQuality` column; regular (iPad)
// renders the bespoke `PadQuality` dashboard (hero + fidelity chart + 5-up tier grid + info card).

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
    .init(id: "preview", name: "Preview", tag: "Fastest request", tris: "Varies", tex: "Source", size: "Varies", time: "Mac", use: "Quick model inspection", psnr: 22),
    .init(id: "reduced", name: "Reduced", tag: "Mobile request", tris: "Varies", tex: "Source", size: "Varies", time: "Mac", use: "On-device RealityKit output", psnr: 28),
    .init(id: "medium", name: "Medium", tag: "Balanced request", tris: "Varies", tex: "Source", size: "Varies", time: "Mac", use: "General-purpose Mac compute", psnr: 33, recommended: true),
    .init(id: "full", name: "Full", tag: "Highest detail", tris: "Varies", tex: "Source", size: "Varies", time: "Mac", use: "High-detail Mac compute", psnr: 38),
    .init(id: "raw", name: "Raw", tag: "Source-preserving", tris: "Varies", tex: "Source", size: "Varies", time: "Mac", use: "Mac archive reconstruction", psnr: 44),
]

/// Resolve the selected tier (falls back to the recommended `medium` tier).
private func detailTier(for id: String) -> DetailTier { DETAIL_TIERS.first { $0.id == id } ?? DETAIL_TIERS[2] }

// MARK: - Adaptive entry point

struct QualityScreen: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var model: StudioModel

    private var sel: Binding<String> {
        Binding(get: { model.selectedDetailTier }, set: { model.selectedDetailTier = $0 })
    }

    var body: some View {
        if hSize == .regular && !dynamicTypeSize.isAccessibilitySize {
            PadQuality(sel: sel)
        } else {
            PhoneQuality(sel: sel)
        }
    }
}

// MARK: - iPhone (compact) — scrolling column

private struct PhoneQuality: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel
    @Binding var sel: String

    private var tier: DetailTier { detailTier(for: sel) }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WizardHeader(step: 3, onBack: { model.go(.briefing) }, onClose: { model.go(.library) })
                    titleBlock
                    scaleStrip
                    TierCard(tier: tier, selected: true, compact: false).padding(.top, 14)
                    alternates
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomCTA {
                StButton(title: "Capture at \(tier.name)", kind: .accent, size: .lg, icon: "bolt", full: true) { model.go(.capture) }
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            StLabel(text: "Mac detail request")
            Text("How much detail?").font(.sf(28, .bold)).tracking(0).foregroundStyle(theme.ink).padding(.top, 6)
            Text("This request travels to a Mac handoff. On-device RealityKit output is always Reduced.")
                .font(.sf(13.5)).foregroundStyle(theme.text2).padding(.top, 8)
        }
        .padding(.top, 18)
    }

    // FAST · BALANCED · ARCHIVE gradient scale with five selectable dots.
    private var scaleStrip: some View {
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
                    ForEach(DETAIL_TIERS, id: \.id) { t in
                        scaleDot(for: t)
                        if t.id != DETAIL_TIERS.last?.id { Spacer() }
                    }
                }
            }
        }
        .padding(.top, 14)
    }

    @ViewBuilder private func scaleDot(for t: DetailTier) -> some View {
        let on = t.id == sel
        Button { sel = t.id } label: {
            VStack(spacing: 6) {
                Circle().fill(on ? theme.accent : theme.card)
                    .frame(width: 13, height: 13)
                    .overlay(Circle().strokeBorder(on ? theme.accent : theme.lineStrong, lineWidth: 2))
                    .background { if on { Circle().fill(theme.accentSoft).frame(width: 19, height: 19) } }
                    .offset(y: -10)
                Text(t.name.uppercased())
                    .font(.mono(9.5, on ? .bold : .medium))
                    .foregroundStyle(on ? theme.ink : theme.text3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(t.name) tier")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // The two non-selected tiers, collapsed into compact rows.
    private var alternates: some View {
        VStack(spacing: 8) {
            ForEach(Array(DETAIL_TIERS.filter { $0.id != sel }.prefix(2)), id: \.id) { t in
                altRow(for: t)
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder private func altRow(for t: DetailTier) -> some View {
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
        .contentShape(Rectangle())
        .onTapGesture { sel = t.id }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(t.name) tier, \(t.tris) triangles, \(t.size), about \(t.time)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - iPad (regular) — two-region dashboard

private struct PadQuality: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel
    @Binding var sel: String

    private var tier: DetailTier { detailTier(for: sel) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            theme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                topRow.padding(.top, 18)
                tierRow.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.top, 16)
                infoCard.padding(.top, 16)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // Back · title block · progress tabs · inline "Capture at {name}" CTA.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                CircleIconButton(icon: "back", size: 38) { model.go(.briefing) }
                VStack(alignment: .leading, spacing: 0) {
                    StLabel(text: "New Scan · Step 3 of 4")
                    Text("Choose Mac detail request").font(.sf(17, .bold)).tracking(0).foregroundStyle(theme.ink).padding(.top, 2)
                }
            }
            Spacer(minLength: 16)
            StStepTabs(current: 2)
            Spacer(minLength: 16)
            StButton(title: "Capture at \(tier.name)", kind: .accent, size: .sm, icon: "bolt") { model.go(.capture) }
        }
    }

    // 1fr · 1fr hero / chart row.
    private var topRow: some View {
        HStack(alignment: .top, spacing: 16) {
            heroCard
            requestCard
        }
    }

    private var heroCard: some View {
        StCard(radius: 22, pad: 22) {
            VStack(alignment: .leading, spacing: 0) {
                StLabel(text: "Apple PhotogrammetrySession")
                Text("Choose a Mac compute request.")
                    .font(.sf(30, .bold)).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                Text("The selected tier travels with a Mac handoff. On-device compute stays at Reduced.")
                    .font(.sf(14)).foregroundStyle(theme.text2).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var requestCard: some View {
        StCard(radius: 22, pad: 22) {
            VStack(alignment: .leading, spacing: 0) {
                StLabel(text: "Selected request", color: theme.accentText)
                Text(tier.name).font(.sf(32, .bold)).foregroundStyle(theme.ink).padding(.top, 8)
                Text(tier.use).font(.sf(14)).foregroundStyle(theme.text2).padding(.top, 8)
                Text("Output size, topology, textures, and duration depend on the captured images and the reconstruction engine.")
                    .font(.sf(13)).foregroundStyle(theme.text3).lineSpacing(3).padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    // Three readable columns prevent labels and metrics from collapsing into vertical text.
    private var tierRow: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
            spacing: 12
        ) {
            ForEach(DETAIL_TIERS, id: \.id) { t in
                TierCard(tier: t, selected: t.id == sel, compact: true) { sel = t.id }
                    .frame(maxWidth: .infinity, minHeight: 184, alignment: .top)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var infoCard: some View {
        StCard(radius: 14, pad: 0) {
            HStack(spacing: 10) {
                StIcon(name: "info", size: 16, color: theme.accent)
                infoText
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    private var infoText: some View {
        (Text("For commercial fidelity, capture at ")
            + Text("Raw").fontWeight(.semibold).foregroundStyle(theme.ink)
            + Text(" and view/share at ")
            + Text("Full").fontWeight(.semibold).foregroundStyle(theme.ink)
            + Text(". Re-derive in the library anytime — your iPhone keeps the archive, your Mac does the heavy lifting."))
            .font(.sf(12.5)).foregroundStyle(theme.text2)
    }
}

// MARK: - Tier mesh-density thumbnail (decorative)

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
                               with: .color(Stone.lo.opacity(0.3 + Double(i) / Double(segs) * 0.4)), lineWidth: 0.5 * scale)
                }
                let cr = 13 * scale
                ctx.fill(Path(ellipseIn: CGRect(x: cx - cr, y: cy - cr, width: cr * 2, height: cr * 2)), with: .color(Stone.mid.opacity(0.9)))
                let hr = 7 * scale
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 4 * scale - hr, y: cy - 4 * scale - hr, width: hr * 2, height: hr * 2)), with: .color(Stone.hi.opacity(0.8)))
            }
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.line, lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

// MARK: - Tier card (full on iPhone, compact 5-up on iPad)

struct TierCard: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let tier: DetailTier
    var selected: Bool
    var compact: Bool
    /// Stretch to fill the available height (iPad 5-up row); off keeps the card content-sized.
    var fill: Bool = false
    var onPick: (() -> Void)?

    @ViewBuilder
    var body: some View {
        if let onPick {
            Button(action: onPick) {
                cardContent
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            cardContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
        }
    }

    private var cardContent: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    TierPreview(tier: tier, size: compact ? 52 : 84)
                    VStack(alignment: .leading, spacing: 0) {
                        if compact {
                            Text(tier.name)
                                .font(.sf(17, .bold))
                                .tracking(0)
                                .foregroundStyle(theme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                            if tier.recommended {
                                tierBadge("BEST").padding(.top, 3)
                            } else if selected {
                                tierBadge("SELECTED").padding(.top, 3)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Text(tier.name).font(.sf(20, .bold)).tracking(0).foregroundStyle(theme.ink)
                                if tier.recommended { tierBadge("BEST") } else if selected { tierBadge("SELECTED") }
                            }
                        }
                        StLabel(text: tier.tag, color: selected ? theme.accentText : theme.text3).padding(.top, 3)
                        if !compact {
                            Text(tier.use).font(.sf(13)).foregroundStyle(theme.text2).lineSpacing(1.5).padding(.top, 6)
                        }
                    }
                    Spacer(minLength: 0)
                }
                statsRow
                    .padding(.top, 12)
                    .overlay(alignment: .top) { StRule() }
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: fill ? CGFloat.infinity : nil, alignment: .topLeading)
            .padding(compact ? 14 : 18)
            .background(RoundedRectangle(cornerRadius: compact ? 18 : 20, style: .continuous).fill(selected ? theme.accentSoft : theme.card))
            .overlay(RoundedRectangle(cornerRadius: compact ? 18 : 20, style: .continuous).strokeBorder(selected ? theme.accentLine : theme.line, lineWidth: selected ? 1 : 0.5))
            .stShadow(theme.cardShadow)
    }

    private var statsRow: some View {
        Group {
            if compact || dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 10
                ) {
                    compactStat("Triangles", tier.tris)
                    compactStat("Textures", tier.tex)
                    compactStat("Size", tier.size)
                    compactStat("Compute", tier.time)
                }
            } else {
                HStack(spacing: 0) {
                    statCell("Triangles", tier.tris, first: true)
                    statCell("Textures", tier.tex)
                    statCell("Size", tier.size)
                    statCell("Compute", tier.time)
                }
            }
        }
    }

    private func compactStat(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            StLabel(text: key)
            Text(value)
                .font(.sf(13, .bold))
                .monospacedDigit()
                .foregroundStyle(theme.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 9px accent capsule (matches the JSX `<Chip style={{fontSize:9}}>`).
    @ViewBuilder private func tierBadge(_ text: String) -> some View {
        Text(text)
            .font(.sf(9, .semibold))
            .tracking(0)
            .foregroundStyle(theme.accentText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(theme.accentSoft))
            .overlay(Capsule().strokeBorder(theme.accentLine, lineWidth: 0.5))
    }

    @ViewBuilder private func statCell(_ k: String, _ v: String, first: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            StLabel(text: k)
            Text(v).font(.sf(compact ? 13 : 15, .bold)).tracking(0).monospacedDigit().foregroundStyle(theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, first ? 0 : 10)
        .overlay(alignment: .leading) { if !first { StRule(vertical: true) } }
    }

    private var accessibilityText: String {
        var parts = ["\(tier.name) tier", tier.tag]
        if tier.recommended { parts.append("recommended") }
        parts.append("\(tier.tris) triangles, \(tier.tex) pixel textures, \(tier.size), about \(tier.time)")
        return parts.joined(separator: ", ")
    }
}
