// Theme.swift — 3DSeen "Studio" design system tokens (ported from studio/ds.jsx)
// Precise-instrument aesthetic: bright, legible, one cobalt accent, refined Liquid Glass.
// Two themes (light / dark). Injected through the SwiftUI environment as `\.theme`.

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Color hex helper

extension Color {
    /// Hex string -> Color. Accepts "#RRGGBB" or "RRGGBB".
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Black with alpha — for ink-tinted lines/fills (e.g. rgba(20,20,24,a)).
    static func ink(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }
}

// MARK: - Shadow tokens (two-layer CSS box-shadow → stacked SwiftUI shadows)

/// A design-system shadow recipe made of one or more stacked layers.
/// CSS `box-shadow` maps to SwiftUI as: radius ≈ blur ÷ 2, `y` direct, `color` = the rgba.
struct StShadow {
    struct Layer {
        var color: Color
        var radius: CGFloat
        var y: CGFloat
        var x: CGFloat = 0
    }
    var layers: [Layer]
}

extension View {
    /// Apply a multi-layer `StShadow` by stacking `.shadow` modifiers (reduce over layers).
    /// An empty `layers` array is a no-op.
    func stShadow(_ s: StShadow) -> some View {
        s.layers.reduce(AnyView(self)) { view, layer in
            AnyView(view.shadow(color: layer.color, radius: layer.radius, x: layer.x, y: layer.y))
        }
    }
}

// MARK: - Theme

enum ThemeMode { case light, dark }

/// A live token bag screens read directly via the environment.
/// Mirrors the LIGHT/DARK sets in studio/ds.jsx 1:1.
struct Theme {
    var mode: ThemeMode

    // surfaces
    var canvas: Color
    var bg: Color
    var bgInset: Color
    var card: Color
    var card2: Color

    // text
    var ink: Color
    var text2: Color
    var text3: Color
    var text4: Color
    var onAccent: Color

    // structure
    var line: Color
    var lineStrong: Color
    var fieldFill: Color
    var fieldFillHi: Color

    // accent (cobalt) + tints
    var accent: Color
    var accentText: Color
    var accentSoft: Color
    var accentLine: Color

    // status
    var good: Color
    var goodSoft: Color
    var warn: Color
    var warnSoft: Color
    var bad: Color
    var badSoft: Color

    // glass
    var glassFill: Color
    var glassBorder: Color
    var glassShine: Color

    // primary button
    var primaryFill: Color
    var primaryText: Color

    // charts
    var grid: Color
    var axis: Color

    // type
    static let sf = "SF Pro Display"
    static let mono = "SF Mono"

    // MARK: stage gradient for 3D content (radial, soft top key light)
    var stage: RadialGradient {
        mode == .dark
            ? RadialGradient(stops: [.init(color: Color(hex: "#2A2A31"), location: 0),
                                     .init(color: Color(hex: "#17171B"), location: 0.55),
                                     .init(color: Color(hex: "#101013"), location: 1)],
                             center: UnitPoint(x: 0.5, y: 0.06), startRadius: 0, endRadius: 760)
            : RadialGradient(stops: [.init(color: Color(hex: "#FCFCFB"), location: 0),
                                     .init(color: Color(hex: "#EFEEE9"), location: 0.52),
                                     .init(color: Color(hex: "#E2E0DA"), location: 1)],
                             center: UnitPoint(x: 0.5, y: 0.08), startRadius: 0, endRadius: 760)
    }

    /// Soft white rim along the top edge of a stage / glass surface.
    var stageRim: Color {
        mode == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.6)
    }

    // MARK: shadow tokens (mode-derived, like `stage`/`shellBackground`)

    /// Floating Liquid Glass panel shadow.
    var glassShadow: StShadow {
        mode == .dark
            ? StShadow(layers: [.init(color: .black.opacity(0.4), radius: 1, y: 1),
                                .init(color: .black.opacity(0.5), radius: 20, y: 16)])
            : StShadow(layers: [.init(color: .ink(20, 20, 30, 0.06), radius: 1, y: 1),
                                .init(color: .ink(20, 20, 30, 0.10), radius: 16, y: 12)])
    }

    /// Resting card shadow.
    var cardShadow: StShadow {
        mode == .dark
            ? StShadow(layers: [.init(color: .black.opacity(0.3), radius: 1, y: 1),
                                .init(color: .black.opacity(0.42), radius: 17, y: 12)])
            : StShadow(layers: [.init(color: .ink(20, 20, 30, 0.04), radius: 1, y: 1),
                                .init(color: .ink(20, 20, 30, 0.06), radius: 15, y: 10)])
    }

    /// Elevated card shadow.
    var cardShadowLg: StShadow {
        mode == .dark
            ? StShadow(layers: [.init(color: .black.opacity(0.4), radius: 4, y: 2),
                                .init(color: .black.opacity(0.55), radius: 35, y: 28)])
            : StShadow(layers: [.init(color: .ink(20, 20, 30, 0.05), radius: 3, y: 2),
                                .init(color: .ink(20, 20, 30, 0.10), radius: 30, y: 24)])
    }

    /// Primary (solid ink) button shadow.
    var primaryShadow: StShadow {
        mode == .dark
            ? StShadow(layers: [.init(color: .black.opacity(0.4), radius: 1, y: 1),
                                .init(color: .black.opacity(0.4), radius: 10, y: 8)])
            : StShadow(layers: [.init(color: .black.opacity(0.18), radius: 1, y: 1),
                                .init(color: .black.opacity(0.16), radius: 8, y: 6)])
    }

    /// Backdrop behind the device frame (Shell background).
    var shellBackground: RadialGradient {
        mode == .dark
            ? RadialGradient(colors: [Color(hex: "#161618"), Color(hex: "#0A0A0C")],
                             center: .top, startRadius: 0, endRadius: 900)
            : RadialGradient(colors: [Color(hex: "#F1EFEA"), Color(hex: "#DEDBD3")],
                             center: .top, startRadius: 0, endRadius: 900)
    }

    // MARK: token sets

    static let light = Theme(
        mode: .light,
        canvas: Color(hex: "#E9E7E1"),
        bg: Color(hex: "#F6F5F2"),
        bgInset: Color(hex: "#EDEBE5"),
        card: Color(hex: "#FFFFFF"),
        card2: Color(hex: "#FBFAF8"),
        ink: Color(hex: "#1B1B1D"),
        text2: .ink(27, 27, 29, 0.72),
        text3: .ink(27, 27, 29, 0.62),
        text4: .ink(27, 27, 29, 0.45),
        onAccent: Color(hex: "#FFFFFF"),
        line: .ink(20, 20, 24, 0.08),
        lineStrong: .ink(20, 20, 24, 0.14),
        fieldFill: .ink(20, 20, 24, 0.045),
        fieldFillHi: .ink(20, 20, 24, 0.075),
        accent: Color(hex: "#2D68F0"),
        accentText: Color(hex: "#1F58DC"),
        accentSoft: Color(.sRGB, red: 45/255, green: 104/255, blue: 240/255, opacity: 0.10),
        accentLine: Color(.sRGB, red: 45/255, green: 104/255, blue: 240/255, opacity: 0.30),
        good: Color(hex: "#167044"),
        goodSoft: Color(.sRGB, red: 30/255, green: 142/255, blue: 90/255, opacity: 0.12),
        warn: Color(hex: "#8A5A00"),
        warnSoft: Color(.sRGB, red: 182/255, green: 121/255, blue: 29/255, opacity: 0.14),
        bad: Color(hex: "#A92E24"),
        badSoft: Color(.sRGB, red: 197/255, green: 59/255, blue: 48/255, opacity: 0.12),
        glassFill: Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.72),
        glassBorder: .ink(20, 20, 24, 0.07),
        glassShine: Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.9),
        primaryFill: Color(hex: "#1B1B1D"),
        primaryText: Color(hex: "#FFFFFF"),
        grid: .ink(20, 20, 24, 0.07),
        axis: .ink(20, 20, 24, 0.16)
    )

    static let dark = Theme(
        mode: .dark,
        canvas: Color(hex: "#0C0C0E"),
        bg: Color(hex: "#161619"),
        bgInset: Color(hex: "#101013"),
        card: Color(hex: "#1F1F25"),
        card2: Color(hex: "#1A1A1F"),
        ink: Color(hex: "#F3F2F5"),
        text2: Color(.sRGB, red: 243/255, green: 242/255, blue: 245/255, opacity: 0.72),
        text3: Color(.sRGB, red: 243/255, green: 242/255, blue: 245/255, opacity: 0.52),
        text4: Color(.sRGB, red: 243/255, green: 242/255, blue: 245/255, opacity: 0.38),
        onAccent: Color(hex: "#0A1124"),
        line: Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.08),
        lineStrong: Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.15),
        fieldFill: Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.06),
        fieldFillHi: Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.10),
        accent: Color(hex: "#5E9BFF"),
        accentText: Color(hex: "#84B2FF"),
        accentSoft: Color(.sRGB, red: 94/255, green: 155/255, blue: 255/255, opacity: 0.16),
        accentLine: Color(.sRGB, red: 94/255, green: 155/255, blue: 255/255, opacity: 0.34),
        good: Color(hex: "#34C77B"),
        goodSoft: Color(.sRGB, red: 52/255, green: 199/255, blue: 123/255, opacity: 0.16),
        warn: Color(hex: "#E0A53F"),
        warnSoft: Color(.sRGB, red: 224/255, green: 165/255, blue: 63/255, opacity: 0.16),
        bad: Color(hex: "#FF6B5E"),
        badSoft: Color(.sRGB, red: 255/255, green: 107/255, blue: 94/255, opacity: 0.16),
        glassFill: Color(.sRGB, red: 34/255, green: 34/255, blue: 40/255, opacity: 0.66),
        glassBorder: Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.10),
        glassShine: Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.14),
        primaryFill: Color(hex: "#F3F2F5"),
        primaryText: Color(hex: "#16161A"),
        grid: Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.07),
        axis: Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.18)
    )

    static func of(_ mode: ThemeMode) -> Theme { mode == .dark ? .dark : .light }
}

// MARK: - Warm stone palette for rendered objects (theme-independent)

enum Stone {
    static let hi = Color(hex: "#ECE4D6")
    static let mid = Color(hex: "#BFA98C")
    static let lo = Color(hex: "#6B5C49")
    static let deep = Color(hex: "#372E24")
}

// MARK: - Environment plumbing

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .light
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Font helpers (SF Pro + SF Mono, tabular numerals)

extension Font {
    /// SF Pro Display/Text at a given size + weight (system font is SF on Apple platforms).
    static func sf(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: scaledPointSize(size, maximumScale: 2), weight: weight)
    }

    /// SF Mono for telemetry / overline labels.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: scaledPointSize(size, maximumScale: 1.5), weight: weight, design: .monospaced)
    }

    private static func scaledPointSize(_ size: CGFloat, maximumScale: CGFloat) -> CGFloat {
        #if canImport(UIKit)
        let metrics = UIFontMetrics(forTextStyle: textStyle(for: size))
        return min(metrics.scaledValue(for: size), size * maximumScale)
        #else
        return size
        #endif
    }

    #if canImport(UIKit)
    private static func textStyle(for size: CGFloat) -> UIFont.TextStyle {
        switch size {
        case 34...: return .largeTitle
        case 28..<34: return .title1
        case 22..<28: return .title2
        case 20..<22: return .title3
        case 17..<20: return .headline
        case 16..<17: return .body
        case 15..<16: return .subheadline
        case 13..<15: return .footnote
        case 11..<13: return .caption1
        default: return .caption2
        }
    }
    #endif
}
