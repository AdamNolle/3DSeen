// LiquidGlass.swift — Apple Liquid Glass material (ported from the `Glass` primitive in ds.jsx)
// A translucent lens that blurs the backdrop, catches a bright specular highlight along its
// top curve, and carries a soft inner shade for depth. `tone: .dark` darkens the lens so light
// content stays legible over dark backgrounds (e.g. the camera feed).

import SwiftUI

enum GlassTone { case auto, dark }

/// Background modifier that paints the Liquid Glass material behind any view.
struct LiquidGlassBackground: ViewModifier {
    @Environment(\.theme) private var theme
    var radius: CGFloat = 18
    var tone: GlassTone = .auto
    var shine: Bool = true

    private var dark: Bool { tone == .dark }

    private var fill: Color {
        dark ? Color(.sRGB, red: 26/255, green: 24/255, blue: 21/255, opacity: 0.52) : theme.glassFill
    }
    private var border: Color {
        dark ? Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.18) : theme.glassBorder
    }
    private var rimTop: Color {
        dark ? Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.55) : theme.glassShine
    }
    private var sheen: Color {
        dark ? Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.12) : Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.38)
    }
    private var innerShade: Color {
        dark ? Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.28) : Color(.sRGB, red: 18/255, green: 18/255, blue: 28/255, opacity: 0.05)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(fill), in: .rect(cornerRadius: radius))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(border, lineWidth: 0.5)
                }
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(rimTop.opacity(shine ? 1 : 0), lineWidth: 0.9)
                        .mask(
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.2))
                        )
                }
                .stShadow(theme.glassShadow)
        } else {
            fallback(content: content)
        }
        #else
        fallback(content: content)
        #endif
    }

    private func fallback(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // blurred backdrop lens
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(fill)
                    if shine {
                        // top specular sheen
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [sheen, .clear],
                                    startPoint: .top, endPoint: .init(x: 0.5, y: 0.26)
                                )
                            )
                        // soft inner bottom shade
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(
                                LinearGradient(colors: [.clear, innerShade],
                                               startPoint: .init(x: 0.5, y: 0.6), endPoint: .bottom)
                            )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: 0.5)
            }
            .overlay(alignment: .top) {
                // bright top rim
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(rimTop.opacity(shine ? 1 : 0), lineWidth: 0.9)
                    .mask(
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.2))
                    )
            }
            .stShadow(theme.glassShadow)
    }
}

extension View {
    /// Apply the Liquid Glass material as a background.
    func liquidGlass(radius: CGFloat = 18, tone: GlassTone = .auto, shine: Bool = true) -> some View {
        modifier(LiquidGlassBackground(radius: radius, tone: tone, shine: shine))
    }
}

/// Container that wraps content in a Liquid Glass panel (mirrors `<Glass>` usage).
struct StGlass<Content: View>: View {
    var radius: CGFloat = 18
    var tone: GlassTone = .auto
    var shine: Bool = true
    @ViewBuilder var content: Content

    @ViewBuilder
    var body: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                content.liquidGlass(radius: radius, tone: tone, shine: shine)
            }
        } else {
            content.liquidGlass(radius: radius, tone: tone, shine: shine)
        }
        #else
        content.liquidGlass(radius: radius, tone: tone, shine: shine)
        #endif
    }
}
