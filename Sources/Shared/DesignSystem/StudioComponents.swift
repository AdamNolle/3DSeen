// StudioComponents.swift — shared screen scaffolding ported from the design prototype.
// Cross-platform (pure SwiftUI, no UIKit) so the iPad/Mac screens share one source of truth.
// Tokens come from the `\.theme` environment; `St`-prefixed to avoid SwiftUI collisions.

import SwiftUI

// MARK: - Step tabs (wizard progress stepper)

/// The capture-wizard progress stepper from `mode.jsx` / `briefing.jsx` (`<StepTabs active=…/>`).
/// Renders numbered pills "1 Mode · 2 Briefing · 3 Detail · 4 Capture"; completed steps show a
/// check, the active step gets the accent badge + a filled pill, later steps stay muted.
/// Used in the iPad headers across mode/briefing/quality/review.
struct StStepTabs: View {
    @Environment(\.theme) private var theme
    /// Labels for each step (default mirrors the capture flow's four stages, in order).
    var steps: [String] = ["Mode", "Briefing", "Detail", "Capture"]
    /// Zero-based index of the active step. Earlier indices render as completed.
    var current: Int

    private var currentLabel: String {
        steps.indices.contains(current) ? steps[current] : "Progress"
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, label in
                let on = i == current
                let done = i < current
                HStack(spacing: 5) {
                    badge(index: i, on: on, done: done)
                    Text(label)
                        .font(.sf(12, on ? .semibold : .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundStyle(on ? theme.ink : theme.text3)
                .padding(.vertical, 6)
                .padding(.horizontal, on ? 8 : 3)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(on ? theme.fieldFillHi : Color.clear)
                )
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(current + 1) of \(steps.count), \(currentLabel)")
    }

    @ViewBuilder private func badge(index: Int, on: Bool, done: Bool) -> some View {
        ZStack {
            Circle().fill(done ? theme.good : on ? theme.accent : theme.fieldFillHi)
            Group {
                if done {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                } else {
                    Text("\(index + 1)").font(.mono(9, .bold))
                }
            }
            .foregroundStyle(done || on ? Color.white : theme.text3)
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - Fidelity chart (quality screen)

/// The fidelity-vs-tier curve from `quality.jsx` (`<FidelityChart/>`): a PSNR line across the five
/// reconstruction tiers with the selected tier marked by a filled accent dot. Faithful Canvas
/// reproduction of the SVG — baseline axis, dashed gridlines, accent connectors, per-tier labels.
struct StFidelityChart: View {
    /// One point on the fidelity curve. `psnr` is the peak signal-to-noise ratio in dB.
    struct Tier {
        var name: String
        var psnr: Int
    }

    @Environment(\.theme) private var theme
    var tiers: [Tier]
    /// Zero-based index of the selected tier (drawn with the enlarged filled marker).
    var selected: Int
    /// Drawing height; width fills the container (matches the prototype's `width: 100%`).
    var height: CGFloat = 170

    /// The canonical five PhotogrammetrySession tiers, for callers that don't supply their own.
    static let defaultTiers: [Tier] = [
        .init(name: "Preview", psnr: 22),
        .init(name: "Reduced", psnr: 28),
        .init(name: "Medium", psnr: 33),
        .init(name: "Full", psnr: 38),
        .init(name: "Raw", psnr: 44),
    ]

    /// PSNR → vertical position, normalized to the 18…46 dB band the prototype plots. Pure
    /// (no SwiftUI), so the curve mapping is unit-testable.
    static func yPosition(psnr: Int, height h: CGFloat) -> CGFloat {
        (h - 28) - (CGFloat(psnr) - 18) / 28 * (h - 56)
    }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height

            // baseline axis
            var base = Path()
            base.move(to: CGPoint(x: 30, y: h - 28))
            base.addLine(to: CGPoint(x: w - 10, y: h - 28))
            ctx.stroke(base, with: .color(theme.axis), lineWidth: 1)

            // dashed gridlines
            for i in 0..<4 {
                let y = 20 + CGFloat(i) * (h - 70) / 3
                var g = Path()
                g.move(to: CGPoint(x: 30, y: y))
                g.addLine(to: CGPoint(x: w - 10, y: y))
                ctx.stroke(g, with: .color(theme.grid), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }

            guard !tiers.isEmpty else { return }
            let n = tiers.count
            func px(_ i: Int) -> CGFloat { 55 + CGFloat(i) * ((w - 80) / CGFloat(max(1, n - 1))) }
            func py(_ psnr: Int) -> CGFloat { Self.yPosition(psnr: psnr, height: h) }

            // accent connectors
            for i in 0..<(n - 1) {
                var line = Path()
                line.move(to: CGPoint(x: px(i), y: py(tiers[i].psnr)))
                line.addLine(to: CGPoint(x: px(i + 1), y: py(tiers[i + 1].psnr)))
                ctx.stroke(line, with: .color(theme.accentLine), lineWidth: 1.5)
            }

            // markers + labels
            for (i, t) in tiers.enumerated() {
                let x = px(i), y = py(t.psnr)
                let on = i == selected
                let r: CGFloat = on ? 7 : 4.5
                let dot = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                ctx.fill(dot, with: .color(on ? theme.accent : theme.card))
                ctx.stroke(dot, with: .color(theme.accent), lineWidth: 1.6)
                ctx.draw(Text(t.name.uppercased()).font(.mono(9)).foregroundStyle(theme.text3),
                         at: CGPoint(x: x, y: h - 12), anchor: .center)
                ctx.draw(Text("\(t.psnr)").font(.sf(11, .bold)).foregroundStyle(theme.ink),
                         at: CGPoint(x: x, y: y - 11), anchor: .center)
            }

            ctx.draw(Text("PSNR dB").font(.mono(9)).foregroundStyle(theme.text3),
                     at: CGPoint(x: 34, y: 16), anchor: .topLeading)
        }
        .frame(height: height)
    }
}

// MARK: - Split pane (iPad two-column scaffold)

/// A reusable two-column iPad scaffold: a wider left stage/hero pane and a right rail/cards pane,
/// separated by the spec's gutter. The iPad screen layouts compose this; `ratio` is the left
/// pane's share of the content width (0…1). Generic over both panes — supply any SwiftUI content.
struct StSplitPane<Left: View, Right: View>: View {
    /// Left pane's fraction of the available width (after the gutter). Default ≈ 58 %.
    var ratio: CGFloat = 0.58
    /// Gutter between the two panes.
    var gap: CGFloat = 20
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    /// Left-pane width for a given container width — pure, so the split math is testable.
    static func leftWidth(total: CGFloat, gap: CGFloat, ratio: CGFloat) -> CGFloat {
        max(0, (total - gap) * min(1, max(0, ratio)))
    }

    var body: some View {
        GeometryReader { geo in
            let leftW = Self.leftWidth(total: geo.size.width, gap: gap, ratio: ratio)
            HStack(spacing: gap) {
                left.frame(width: leftW, height: geo.size.height)
                right.frame(width: max(0, geo.size.width - gap - leftW), height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
