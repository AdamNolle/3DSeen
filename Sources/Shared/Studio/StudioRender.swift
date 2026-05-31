// StudioRender.swift — premium rendered content (ported from studio/render.jsx).
// Warm-stone materials on a neutral studio stage. 3D model, coverage maps, thumbnails, charts.
// SVG sources are recreated with SwiftUI Canvas / Shapes.

import SwiftUI

// MARK: - Stage (neutral studio backdrop for 3D content)

struct Stage<Content: View>: View {
    @Environment(\.theme) private var theme
    var radius: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(theme.stage))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(theme.mode == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.6), lineWidth: 0.5)
            )
    }
}

// MARK: - Scan tones

enum ScanTone {
    /// (high, low) stone colours per tone name.
    static func pair(_ tone: String) -> (Color, Color) {
        switch tone {
        case "rust":     return (Color(hex: "#D8AE7E"), Color(hex: "#7A4F2E"))
        case "walnut":   return (Color(hex: "#C0A079"), Color(hex: "#5E4129"))
        case "graphite": return (Color(hex: "#D2D4D8"), Color(hex: "#5A5E66"))
        case "slate":    return (Color(hex: "#AEB9BD"), Color(hex: "#4C5A60"))
        case "ice":      return (Color(hex: "#CFE0E2"), Color(hex: "#566C70"))
        default:         return (Color(hex: "#EFE7D7"), Color(hex: "#9B8769")) // bone
        }
    }
}

// MARK: - Hero 3D model (classical bust, warm stone)

struct HeroModel: View {
    @Environment(\.theme) private var theme
    var material: String = "pbr"   // pbr / wire / metal / matte
    var accent: Color?

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 600
            Canvas { ctx, _ in
                ctx.scaleBy(x: s, y: s)
                let a = accent ?? theme.accent
                let metal = material == "metal"
                let baseHi = metal ? Color(hex: "#F1EEE9") : Stone.hi
                let baseMid = metal ? Color(hex: "#9A9DA2") : Stone.mid
                let baseLo = metal ? Color(hex: "#3B3E42") : Stone.lo

                // contact shadow
                ctx.fill(Path(ellipseIn: CGRect(x: 150, y: 523, width: 300, height: 44)),
                         with: .color(.black.opacity(0.18)))
                // plinth
                let plinth = Path(roundedRect: CGRect(x: 206, y: 512, width: 188, height: 40), cornerRadius: 4)
                ctx.fill(plinth, with: .linearGradient(
                    Gradient(colors: [theme.mode == .dark ? Color(hex: "#33333A") : Color(hex: "#D8D5CD"),
                                      theme.mode == .dark ? Color(hex: "#1A1A1E") : Color(hex: "#B7B3A8")]),
                    startPoint: CGPoint(x: 300, y: 512), endPoint: CGPoint(x: 300, y: 552)))

                let bodyShading = GraphicsContext.Shading.radialGradient(
                    Gradient(stops: [.init(color: baseHi, location: 0), .init(color: baseMid, location: 0.48), .init(color: baseLo, location: 1)]),
                    center: CGPoint(x: 240, y: 192), startRadius: 0, endRadius: 468)

                if material == "wire" {
                    // simplified wireframe: stacked ellipses + meridian lines
                    for i in 0..<8 {
                        let r = 92 - CGFloat(i) * 6
                        let cy = 512 - CGFloat(i) * 28
                        ctx.stroke(Path(ellipseIn: CGRect(x: 300 - r, y: cy - (5 + CGFloat(i)), width: r * 2, height: (5 + CGFloat(i)) * 2)),
                                   with: .color(a.opacity(0.8)), lineWidth: 0.7)
                    }
                    ctx.stroke(Path(ellipseIn: CGRect(x: 222, y: 82, width: 156, height: 200)),
                               with: .color(a.opacity(0.8)), lineWidth: 0.7)
                } else {
                    // body
                    var body = Path()
                    body.move(to: CGPoint(x: 212, y: 512))
                    body.addCurve(to: CGPoint(x: 242, y: 322), control1: CGPoint(x: 222, y: 432), control2: CGPoint(x: 232, y: 372))
                    body.addCurve(to: CGPoint(x: 300, y: 282), control1: CGPoint(x: 252, y: 292), control2: CGPoint(x: 272, y: 282))
                    body.addCurve(to: CGPoint(x: 358, y: 322), control1: CGPoint(x: 328, y: 282), control2: CGPoint(x: 348, y: 292))
                    body.addCurve(to: CGPoint(x: 388, y: 512), control1: CGPoint(x: 368, y: 432), control2: CGPoint(x: 378, y: 432))
                    body.closeSubpath()
                    ctx.fill(body, with: bodyShading)
                    // neck
                    var neck = Path()
                    neck.move(to: CGPoint(x: 272, y: 292))
                    neck.addCurve(to: CGPoint(x: 287, y: 202), control1: CGPoint(x: 272, y: 252), control2: CGPoint(x: 272, y: 222))
                    neck.addLine(to: CGPoint(x: 313, y: 202))
                    neck.addCurve(to: CGPoint(x: 328, y: 292), control1: CGPoint(x: 328, y: 222), control2: CGPoint(x: 328, y: 252))
                    ctx.fill(neck, with: bodyShading)
                    // head
                    ctx.fill(Path(ellipseIn: CGRect(x: 222, y: 82, width: 156, height: 200)), with: bodyShading)
                    // face (dark)
                    ctx.fill(Path(ellipseIn: CGRect(x: 246, y: 102, width: 108, height: 130)),
                             with: .color(metal ? Color(hex: "#52565B") : Stone.deep))
                    // highlight
                    ctx.fill(Path(ellipseIn: CGRect(x: 228, y: 88, width: 108, height: 148)),
                             with: .radialGradient(Gradient(colors: [.white.opacity(0.85), .white.opacity(0)]),
                                                   center: CGPoint(x: 282, y: 162), startRadius: 0, endRadius: 74))
                    // accent rim
                    ctx.fill(Path(ellipseIn: CGRect(x: 242, y: 60, width: 160, height: 440)),
                             with: .radialGradient(Gradient(colors: [a.opacity(material == "matte" ? 0.18 : 0.42), a.opacity(0)]),
                                                   center: CGPoint(x: 322, y: 280), startRadius: 0, endRadius: 230))
                }
            }
        }
    }
}

// MARK: - Coverage sphere (viewfinder, compact)

struct CoverageSphere: View {
    @Environment(\.theme) private var theme
    var pct: Int = 72
    private let wedges = 22
    private let covered: Set<Int> = [0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 13, 15, 16, 17, 18]
    private let partial: Set<Int> = [6, 12, 19]

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2, cy = size.height / 2
            func pp(_ ang: Double, _ r: Double) -> CGPoint {
                CGPoint(x: cx + cos(ang) * r, y: cy + sin(ang) * r * 0.34)
            }
            let scale = size.width / 210
            // latitude rings
            for lat in stride(from: -60.0, through: 60.0, by: 30.0) {
                let rx = 96 * cos(lat * .pi / 180) * scale
                let ry = rx * 0.34
                let rect = CGRect(x: cx - rx, y: cy + lat * 0.6 * scale - ry, width: rx * 2, height: ry * 2)
                ctx.stroke(Path(ellipseIn: rect), with: .color(theme.grid), lineWidth: 0.5)
            }
            // wedges
            for i in 0..<wedges {
                let a1 = Double(i) / Double(wedges) * .pi * 2
                let a2 = Double(i + 1) / Double(wedges) * .pi * 2
                let r1 = 66.0 * scale, r2 = 92.0 * scale
                var p = Path()
                p.move(to: pp(a1, r1))
                p.addLine(to: pp(a2, r1))
                p.addLine(to: pp(a2, r2))
                p.addLine(to: pp(a1, r2))
                p.closeSubpath()
                let c = covered.contains(i) ? theme.good : partial.contains(i) ? theme.warn : theme.bad
                let op = covered.contains(i) ? 0.42 : 0.6
                ctx.fill(p, with: .color(c.opacity(op)))
                ctx.stroke(p, with: .color(c.opacity(0.3)), lineWidth: 0.4)
            }
            // core
            let coreR = 20.0 * scale
            ctx.fill(Path(ellipseIn: CGRect(x: cx - coreR, y: cy - coreR, width: coreR * 2, height: coreR * 2)),
                     with: .radialGradient(Gradient(colors: [Stone.hi, Stone.mid.opacity(0.85), Stone.deep.opacity(0.2)]),
                                           center: CGPoint(x: cx - coreR * 0.3, y: cy - coreR * 0.3), startRadius: 0, endRadius: coreR * 1.6))
        }
    }
}

// MARK: - Coverage dome (review, with numbered dropout pins)

struct CoverageDome: View {
    @Environment(\.theme) private var theme
    var drops: [Dropout] = []

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Canvas { ctx, sz in
                    let cx = sz.width / 2, cy = sz.height * 0.5
                    let scale = sz.width / 220
                    func pp(_ ang: Double, _ r: Double, _ ry: Double) -> CGPoint {
                        CGPoint(x: cx + cos(ang) * r, y: cy + sin(ang) * ry)
                    }
                    for (ri, rBase) in [78.0, 63.0, 48.0].enumerated() {
                        let r = rBase * scale
                        let ry = r * 0.46
                        for i in 0..<30 {
                            let a1 = Double(i) / 30 * .pi * 2 - .pi / 2
                            let a2 = Double(i + 1) / 30 * .pi * 2 - .pi / 2
                            let f = (i + ri * 3) % 30
                            let isBad = (f >= 8 && f <= 10) || f == 21
                            let isWarn = f == 7 || f == 11 || f == 20 || f == 22
                            let c = isBad ? theme.bad : isWarn ? theme.warn : theme.good
                            let op = isBad ? 0.62 : isWarn ? 0.5 : 0.30
                            var p = Path()
                            p.move(to: CGPoint(x: cx, y: cy))
                            p.addLine(to: pp(a1, r, ry))
                            p.addLine(to: pp(a2, r, ry))
                            p.closeSubpath()
                            ctx.fill(p, with: .color(c.opacity(op * (0.92 - Double(ri) * 0.12))))
                        }
                    }
                    // core
                    let coreR = 22.0 * scale
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - coreR, y: cy - coreR * 0.6, width: coreR * 2, height: coreR * 2.6)),
                             with: .radialGradient(Gradient(colors: [Stone.hi, Stone.mid, Stone.deep]),
                                                   center: CGPoint(x: cx - coreR * 0.2, y: cy), startRadius: 0, endRadius: coreR * 2))
                }
                // numbered dropout pins
                ForEach(Array(drops.enumerated()), id: \.element.id) { idx, d in
                    let px = size.width / 2 + (d.x - 50) / 50 * (size.width * 0.345)
                    let py = size.height * 0.5 + (d.y - 50) / 50 * (size.height * 0.345)
                    let c = d.severity == "high" ? theme.bad : d.severity == "med" ? theme.warn : theme.accent
                    Circle().fill(theme.card).overlay(Circle().strokeBorder(c, lineWidth: 1.6))
                        .frame(width: 16, height: 16)
                        .overlay(Text("\(idx + 1)").font(.sf(9, .bold)).foregroundStyle(c))
                        .position(x: px, y: py)
                }
            }
        }
    }
}

// MARK: - Sparkline

struct Spark: View {
    @Environment(\.theme) private var theme
    var values: [Double]
    var color: Color?
    var fill: Bool = true

    var body: some View {
        let c = color ?? theme.accent
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let maxV = values.max()!, minV = values.min()!
            let range = (maxV - minV) == 0 ? 1 : (maxV - minV)
            func pt(_ i: Int) -> CGPoint {
                let x = Double(i) / Double(values.count - 1) * size.width
                let y = size.height - (values[i] - minV) / range * (size.height - 5) - 2.5
                return CGPoint(x: x, y: y)
            }
            var line = Path()
            line.move(to: pt(0))
            for i in 1..<values.count { line.addLine(to: pt(i)) }
            if fill {
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                ctx.fill(area, with: .color(c.opacity(0.10)))
            }
            ctx.stroke(line, with: .color(c), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            let last = pt(values.count - 1)
            ctx.fill(Path(ellipseIn: CGRect(x: last.x - 2.4, y: last.y - 2.4, width: 4.8, height: 4.8)), with: .color(c))
        }
    }
}

// MARK: - RGB luma histogram

struct Histogram: View {
    @Environment(\.theme) private var theme

    private func make(_ off: Double, _ amp: Double) -> [Double] {
        (0..<48).map { i in
            let x = (Double(i) - 24 + off) / 12
            return exp(-x * x) * amp + Double((i * 7) % 5) / 40
        }
    }

    var body: some View {
        let chans: [(Color, [Double])] = [
            (Color(hex: "#D06A66"), make(2, 0.85)),
            (Color(hex: "#5BA86E"), make(0, 1)),
            (Color(hex: "#5B85C8"), make(-3, 0.7)),
        ]
        Canvas { ctx, size in
            for t in [0.25, 0.5, 0.75] {
                var g = Path()
                g.move(to: CGPoint(x: t * size.width, y: 0))
                g.addLine(to: CGPoint(x: t * size.width, y: size.height))
                ctx.stroke(g, with: .color(theme.grid), lineWidth: 0.5)
            }
            for (c, arr) in chans {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: size.height))
                for (i, v) in arr.enumerated() {
                    let x = Double(i) / Double(arr.count - 1) * size.width
                    let y = size.height - min(1, v) * (size.height - 2)
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                p.addLine(to: CGPoint(x: size.width, y: size.height))
                p.closeSubpath()
                ctx.fill(p, with: .color(c.opacity(0.28)))
                ctx.stroke(p, with: .color(c.opacity(0.7)), lineWidth: 0.9)
            }
        }
    }
}

// MARK: - Frame strip

struct FrameStrip: View {
    @Environment(\.theme) private var theme
    var count: Int = 12
    var sel: Int = -1
    var height: CGFloat = 40

    private let tones: [(Color, Color)] = [
        (Color(hex: "#EFE7D7"), Color(hex: "#9B8769")),
        (Color(hex: "#D8C3A4"), Color(hex: "#7A6244")),
        (Color(hex: "#CBB592"), Color(hex: "#5E4B30")),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                let rej = i == Int(Double(count) * 0.34) || i == Int(Double(count) * 0.72)
                let on = i == sel
                let (a, b) = tones[i % 3]
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(rej ? AnyShapeStyle(theme.badSoft)
                                  : AnyShapeStyle(RadialGradient(colors: [a, b], center: .init(x: 0.38, y: 0.32), startRadius: 0, endRadius: 30)))
                    if rej { Text("×").font(.sf(13, .bold)).foregroundStyle(theme.bad) }
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(on ? theme.accent : rej ? theme.bad : theme.line, lineWidth: on ? 1.5 : 0.5)
                )
                .opacity(rej ? 0.7 : 1)
            }
        }
    }
}

// MARK: - Scan thumbnail (library)

struct ScanThumb: View {
    @Environment(\.theme) private var theme
    let scan: ScanItem
    var radius: CGFloat = 14
    var label: Bool = true

    var body: some View {
        let (hi, lo) = ScanTone.pair(scan.tone)
        ZStack {
            // stage background
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(RadialGradient(
                    colors: theme.mode == .dark ? [Color(hex: "#2b2b31"), Color(hex: "#161618")] : [Color(hex: "#FAFAF8"), Color(hex: "#E7E5DF")],
                    center: .top, startRadius: 0, endRadius: 200))
            // stone object
            Canvas { ctx, size in
                let sx = size.width / 100, sy = size.height / 116
                ctx.fill(Path(ellipseIn: CGRect(x: 24 * sx, y: 88.6 * sy, width: 52 * sx, height: 6.8 * sy)),
                         with: .color(.black.opacity(0.16)))
                ctx.fill(Path(ellipseIn: CGRect(x: 23 * sx, y: 23 * sy, width: 54 * sx, height: 66 * sy)),
                         with: .radialGradient(Gradient(stops: [.init(color: hi, location: 0), .init(color: lo, location: 0.7), .init(color: lo.opacity(0.4), location: 1)]),
                                               center: CGPoint(x: 40 * sx, y: 37 * sy), startRadius: 0, endRadius: 45 * sx))
                ctx.fill(Path(ellipseIn: CGRect(x: 29 * sx, y: 28 * sy, width: 26 * sx, height: 36 * sy)),
                         with: .color(.white.opacity(0.4)))
            }
            // mode chip top-left
            VStack {
                HStack {
                    Text(scan.mode.uppercased())
                        .font(.sf(9, .bold)).tracking(0.4)
                        .foregroundStyle(theme.text2)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(theme.glassFill))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.glassBorder, lineWidth: 0.5))
                    Spacer()
                }
                Spacer()
            }
            .padding(9)
            // label gradient bottom
            if label {
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 3) {
                        Text(scan.name).font(.sf(13, .semibold)).tracking(-0.3).foregroundStyle(theme.ink)
                        Text("\(scan.mode) · \(scan.tier) · \(scan.mb) MB")
                            .font(.mono(9.5)).foregroundStyle(theme.text3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11).padding(.top, 22).padding(.bottom, 10)
                    .background(
                        LinearGradient(colors: theme.mode == .dark ? [.clear, .black.opacity(0.7)] : [.clear, .white.opacity(0.85)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                }
            }
        }
        .aspectRatio(1 / 1.16, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(theme.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 6)
    }
}
