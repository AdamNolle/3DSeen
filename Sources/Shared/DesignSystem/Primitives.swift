// Primitives.swift — Studio component library (ported from studio/ds.jsx + icons.jsx)
// Namespaced with `St` to avoid collisions with SwiftUI's Button/Label/Toggle/etc.

import SwiftUI

// MARK: - Icon (maps the ds.jsx stroke set to SF Symbols)

struct StIcon: View {
    let name: String
    var size: CGFloat = 18
    var color: Color?
    var weight: Font.Weight = .medium

    private static let map: [String: String] = [
        "back": "chevron.left", "chev": "chevron.right", "chevDown": "chevron.down",
        "close": "xmark", "plus": "plus", "check": "checkmark",
        "search": "magnifyingglass", "more": "ellipsis", "grid": "square.grid.2x2",
        "list": "list.bullet", "settings": "gearshape",
        "cube": "cube", "room": "house", "landscape": "mountain.2", "sparkle": "sparkles",
        "camera": "camera", "scan": "viewfinder", "bolt": "bolt.fill", "chip": "cpu",
        "laptop": "laptopcomputer", "phone": "iphone", "tablet": "ipad",
        "thermal": "thermometer.medium", "ruler": "ruler", "layers": "square.stack.3d.up",
        "share": "square.and.arrow.up", "export": "square.and.arrow.up",
        "download": "square.and.arrow.down", "airdrop": "dot.radiowaves.up.forward",
        "pin": "mappin", "light": "sun.max", "focus": "camera.metering.spot",
        "refresh": "arrow.triangle.2.circlepath", "speed": "gauge.with.dots.needle.50percent",
        "hand": "hand.raised", "warning": "exclamationmark.triangle", "info": "info.circle",
        "clock": "clock", "folder": "folder", "cloud": "cloud", "lock": "lock",
        "user": "person", "globe": "globe", "wifi": "wifi", "battery": "battery.75",
        "play": "play.fill", "trash": "trash", "copy": "doc.on.doc",
    ]

    var body: some View {
        Image(systemName: Self.map[name] ?? "questionmark")
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color ?? .primary)
    }
}

// MARK: - Card (solid raised surface)

struct StCard<Content: View>: View {
    @Environment(\.theme) private var theme
    var radius: CGFloat = 20
    var pad: CGFloat = 0
    var elevated: Bool = false
    var inset: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(pad)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(inset ? theme.bgInset : theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(theme.line, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(inset ? 0 : (elevated ? 0.10 : 0.06)),
                    radius: inset ? 0 : (elevated ? 24 : 10), x: 0, y: inset ? 0 : (elevated ? 12 : 6))
    }
}

// MARK: - Button

enum StButtonKind { case primary, accent, secondary, ghost, glass }
enum StButtonSize { case lg, md, sm }

struct StButton: View {
    @Environment(\.theme) private var theme
    var title: String
    var kind: StButtonKind = .secondary
    var size: StButtonSize = .md
    var icon: String?
    var full: Bool = false
    var action: () -> Void = {}

    private var height: CGFloat { size == .lg ? 52 : size == .sm ? 36 : 44 }
    private var fontSize: CGFloat { size == .lg ? 16 : size == .sm ? 13.5 : 15 }
    private var hPad: CGFloat { size == .sm ? 14 : 20 }

    private var fg: Color {
        switch kind {
        case .primary: return theme.primaryText
        case .accent: return theme.onAccent
        case .secondary, .glass: return theme.ink
        case .ghost: return theme.text2
        }
    }
    @ViewBuilder private var bg: some View {
        switch kind {
        case .primary: Capsule().fill(theme.primaryFill)
        case .accent: Capsule().fill(theme.accent)
        case .secondary: Capsule().fill(theme.fieldFill).overlay(Capsule().strokeBorder(theme.line, lineWidth: 0.5))
        case .ghost: Capsule().fill(.clear)
        case .glass: Capsule().fill(theme.glassFill)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { StIcon(name: icon, size: fontSize, color: fg, weight: .semibold) }
                Text(title)
            }
            .font(.sf(fontSize, .semibold))
            .tracking(-0.2)
            .foregroundStyle(fg)
            .frame(maxWidth: full ? .infinity : nil)
            .frame(height: height)
            .padding(.horizontal, hPad)
            .background(bg)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Label (mono overline)

struct StLabel: View {
    @Environment(\.theme) private var theme
    var text: String
    var color: Color?
    var body: some View {
        Text(text.uppercased())
            .font(.mono(10.5, .semibold))
            .tracking(1.4)
            .foregroundStyle(color ?? theme.text3)
    }
}

// MARK: - Stat (keyed numeric readout)

enum StStatSize { case xl, lg, md, sm }

struct StStat: View {
    @Environment(\.theme) private var theme
    var k: String
    var v: String
    var unit: String?
    var color: Color?
    var size: StStatSize = .md
    var align: HorizontalAlignment = .leading

    private var fontSize: CGFloat { size == .xl ? 40 : size == .lg ? 28 : size == .sm ? 17 : 22 }

    var body: some View {
        VStack(alignment: align, spacing: 3) {
            Text(k.uppercased())
                .font(.mono(9.5, .semibold))
                .tracking(1)
                .foregroundStyle(theme.text3)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(v)
                    .font(.sf(fontSize, .bold))
                    .tracking(-0.6)
                    .monospacedDigit()
                    .foregroundStyle(color ?? theme.ink)
                if let unit {
                    Text(unit)
                        .font(.sf(fontSize * 0.46, .semibold))
                        .foregroundStyle(theme.text3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : (align == .trailing ? .trailing : .center))
    }
}

// MARK: - Segmented control

struct StSegmented: View {
    @Environment(\.theme) private var theme
    var options: [(value: String, label: String)]
    @Binding var value: String
    var size: StButtonSize = .md

    private var height: CGFloat { size == .sm ? 30 : 36 }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { o in
                let on = o.value == value
                Button { value = o.value } label: {
                    Text(o.label)
                        .font(.sf(size == .sm ? 12.5 : 13.5, .semibold))
                        .tracking(-0.1)
                        .foregroundStyle(on ? theme.ink : theme.text2)
                        .frame(height: height)
                        .padding(.horizontal, 14)
                        .background(
                            Capsule().fill(on ? theme.card : .clear)
                                .shadow(color: .black.opacity(on ? 0.10 : 0), radius: on ? 2 : 0, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(theme.fieldFill).overlay(Capsule().strokeBorder(theme.line, lineWidth: 0.5)))
    }
}

// MARK: - Toggle switch

struct StToggle: View {
    @Environment(\.theme) private var theme
    @Binding var on: Bool
    var body: some View {
        Button { on.toggle() } label: {
            HStack {
                if on { Spacer(minLength: 0) }
                Circle().fill(.white)
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                if !on { Spacer(minLength: 0) }
            }
            .padding(2)
            .frame(width: 50, height: 30)
            .background(Capsule().fill(on ? theme.good : theme.fieldFillHi))
            .overlay(Capsule().strokeBorder(on ? .clear : theme.line, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: on)
    }
}

// MARK: - Chip / pill

enum StChipTone { case neutral, accent, good, warn, bad }

struct StChip<Content: View>: View {
    @Environment(\.theme) private var theme
    var tone: StChipTone = .neutral
    @ViewBuilder var content: Content

    private var colors: (bg: Color, fg: Color, line: Color) {
        switch tone {
        case .neutral: return (theme.fieldFill, theme.text2, theme.line)
        case .accent: return (theme.accentSoft, theme.accentText, theme.accentLine)
        case .good: return (theme.goodSoft, theme.good, .clear)
        case .warn: return (theme.warnSoft, theme.warn, .clear)
        case .bad: return (theme.badSoft, theme.bad, .clear)
        }
    }

    var body: some View {
        let c = colors
        HStack(spacing: 5) { content }
            .font(.sf(12, .semibold))
            .tracking(-0.1)
            .foregroundStyle(c.fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(c.bg))
            .overlay(Capsule().strokeBorder(c.line, lineWidth: 0.5))
    }
}

/// Text-only chip convenience.
struct StTextChip: View {
    var text: String
    var tone: StChipTone = .neutral
    var icon: String?
    var body: some View {
        StChip(tone: tone) {
            if let icon { StIcon(name: icon, size: 11, weight: .semibold) }
            Text(text)
        }
    }
}

// MARK: - Meter bar

struct StMeter: View {
    @Environment(\.theme) private var theme
    var value: Double = 0.5
    var color: Color?
    var track: Color?
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track ?? theme.fieldFillHi)
                Capsule().fill(color ?? theme.accent)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Progress ring

struct StRing: View {
    @Environment(\.theme) private var theme
    var value: Double = 0.8
    var size: CGFloat = 72
    var stroke: CGFloat = 7
    var color: Color?
    var label: String?
    var sub: String?

    var body: some View {
        ZStack {
            Circle().stroke(theme.fieldFillHi, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: max(0, min(1, value)))
                .stroke(color ?? theme.accent, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                if let label {
                    Text(label)
                        .font(.sf(size * 0.3, .bold))
                        .tracking(-0.5)
                        .monospacedDigit()
                        .foregroundStyle(theme.ink)
                }
                if let sub {
                    Text(sub.uppercased())
                        .font(.mono(8.5, .semibold))
                        .tracking(1)
                        .foregroundStyle(theme.text3)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Hairline divider

struct StRule: View {
    @Environment(\.theme) private var theme
    var vertical: Bool = false
    var body: some View {
        Rectangle().fill(theme.line)
            .frame(width: vertical ? 0.5 : nil, height: vertical ? nil : 0.5)
    }
}
