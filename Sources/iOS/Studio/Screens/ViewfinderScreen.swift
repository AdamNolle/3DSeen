// ViewfinderScreen.swift — live capture (iPhone), ported from screens/viewfinder.jsx (PhoneViewfinder)
// Dark Liquid Glass overlays float over the camera feed; telemetry is a single tidy capsule.

import SwiftUI

// MARK: - Camera feed (dim studio with subject bust)

struct CameraFeed: View {
    var body: some View {
        ZStack {
            Color(hex: "#0B0A09")
            RadialGradient(colors: [Color(hex: "#1f1914"), Color(hex: "#0d0b09"), Color(hex: "#060504")],
                           center: .init(x: 0.5, y: 0.54), startRadius: 0, endRadius: 520)
            // warm key light
            RadialGradient(colors: [Color(.sRGB, red: 1, green: 214/255, blue: 168/255, opacity: 0.12), .clear],
                           center: .init(x: 0.0, y: 0.3), startRadius: 0, endRadius: 360)
                .blendMode(.screen)
            // subject bust
            GeometryReader { _ in
                Canvas { ctx, size in
                    let sx = size.width / 402, sy = size.height / 874
                    // contact shadow
                    ctx.fill(Path(ellipseIn: CGRect(x: 81 * sx, y: 584 * sy, width: 240 * sx, height: 32 * sy)),
                             with: .color(.black.opacity(0.65)))
                    // plinth
                    ctx.fill(Path(roundedRect: CGRect(x: 135 * sx, y: 560 * sy, width: 132 * sx, height: 44 * sy), cornerRadius: 3),
                             with: .color(Color(hex: "#15110d")))
                    let bodyShade = GraphicsContext.Shading.radialGradient(
                        Gradient(stops: [.init(color: Color(hex: "#EBCFA9"), location: 0),
                                         .init(color: Color(hex: "#9B7A5B"), location: 0.42),
                                         .init(color: Color(hex: "#1c130c"), location: 1)]),
                        center: CGPoint(x: 169 * sx, y: 297 * sy), startRadius: 0, endRadius: 280 * sx)
                    // body
                    var body = Path()
                    body.move(to: CGPoint(x: 142 * sx, y: 560 * sy))
                    body.addCurve(to: CGPoint(x: 168 * sx, y: 392 * sy), control1: CGPoint(x: 150 * sx, y: 480 * sy), control2: CGPoint(x: 160 * sx, y: 430 * sy))
                    body.addCurve(to: CGPoint(x: 201 * sx, y: 358 * sy), control1: CGPoint(x: 176 * sx, y: 366 * sy), control2: CGPoint(x: 190 * sx, y: 358 * sy))
                    body.addCurve(to: CGPoint(x: 234 * sx, y: 392 * sy), control1: CGPoint(x: 212 * sx, y: 358 * sy), control2: CGPoint(x: 226 * sx, y: 366 * sy))
                    body.addCurve(to: CGPoint(x: 260 * sx, y: 560 * sy), control1: CGPoint(x: 242 * sx, y: 430 * sy), control2: CGPoint(x: 252 * sx, y: 480 * sy))
                    body.closeSubpath()
                    ctx.fill(body, with: bodyShade)
                    // head
                    ctx.fill(Path(ellipseIn: CGRect(x: 145 * sx, y: 228 * sy, width: 112 * sx, height: 144 * sy)), with: bodyShade)
                    // face (dark)
                    ctx.fill(Path(ellipseIn: CGRect(x: 168 * sx, y: 244 * sy, width: 66 * sx, height: 84 * sy)), with: .color(Color(hex: "#241a12")))
                    // highlight
                    ctx.fill(Path(ellipseIn: CGRect(x: 146 * sx, y: 236 * sy, width: 76 * sx, height: 104 * sy)),
                             with: .radialGradient(Gradient(colors: [Color(.sRGB, red: 1, green: 228/255, blue: 190/255, opacity: 0.6), .clear]),
                                                   center: CGPoint(x: 184 * sx, y: 288 * sy), startRadius: 0, endRadius: 52 * sx))
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - AR bounding box (corner brackets + dimension caliper)

struct ARBox: View {
    @Environment(\.theme) private var theme
    /// box in 402x874 design space: [x1,y1,x2,y2]
    var box: [CGFloat]
    var dim: String

    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 402, sy = size.height / 874
            let x1 = box[0] * sx, y1 = box[1] * sy, x2 = box[2] * sx, y2 = box[3] * sy
            let k: CGFloat = 20
            // faint full rect
            ctx.stroke(Path(roundedRect: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1), cornerRadius: 8),
                       with: .color(.white.opacity(0.20)), lineWidth: 1)
            // corner brackets
            for (cx, cy, dx, dy) in [(x1, y1, 1.0, 1.0), (x2, y1, -1.0, 1.0), (x1, y2, 1.0, -1.0), (x2, y2, -1.0, -1.0)] {
                var p = Path()
                p.move(to: CGPoint(x: cx + dx * k, y: cy))
                p.addLine(to: CGPoint(x: cx + dx * 6, y: cy))
                p.addQuadCurve(to: CGPoint(x: cx, y: cy + dy * 6), control: CGPoint(x: cx, y: cy))
                p.addLine(to: CGPoint(x: cx, y: cy + dy * k))
                ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
            // caliper on left
            var cal = Path()
            cal.move(to: CGPoint(x: x1 - 13, y: y1)); cal.addLine(to: CGPoint(x: x1 - 13, y: y2))
            cal.move(to: CGPoint(x: x1 - 16, y: y1)); cal.addLine(to: CGPoint(x: x1 - 10, y: y1))
            cal.move(to: CGPoint(x: x1 - 16, y: y2)); cal.addLine(to: CGPoint(x: x1 - 10, y: y2))
            ctx.stroke(cal, with: .color(.white.opacity(0.55)), lineWidth: 0.8)
            let txt = ctx.resolve(Text(dim).font(.mono(9, .semibold)).foregroundColor(.white.opacity(0.85)))
            ctx.draw(txt, at: CGPoint(x: x1 - 20, y: (y1 + y2) / 2), anchor: .trailing)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Dark-glass helpers

struct DLabel: View {
    var text: String
    var color: Color = .white.opacity(0.55)
    var body: some View {
        Text(text.uppercased()).font(.mono(9.5, .semibold)).tracking(1.3).foregroundStyle(color)
    }
}

struct DarkTelemetry: View {
    /// (key, value, color?)
    var items: [(String, String, Color?)]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                VStack(spacing: 3) {
                    Text(it.0).font(.mono(8.5, .semibold)).tracking(1).foregroundStyle(.white.opacity(0.55))
                    Text(it.1).font(.mono(13, .bold)).foregroundStyle(it.2 ?? .white)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(.white.opacity(0.12)).frame(width: 0.5) } }
            }
        }
        .padding(.vertical, 9).padding(.horizontal, 4)
        .liquidGlass(radius: 15, tone: .dark)
    }
}

struct Shutter: View {
    @Environment(\.theme) private var theme
    var size: CGFloat = 74
    var action: () -> Void
    var body: some View {
        Button {
            Haptics.impact(.heavy)
            action()
        } label: {
            Circle().fill(.white).frame(width: size, height: size)
                .overlay(Circle().strokeBorder(.black.opacity(0.85), lineWidth: 2.5))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.bad).padding(7))
                .shadow(color: .black.opacity(0.45), radius: 9, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capture")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Screen

struct ViewfinderScreen: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        ZStack {
            CameraFeed()
            ARBox(box: [124, 250, 278, 548], dim: "14.2 cm").ignoresSafeArea()

            VStack(spacing: 0) {
                // top bar
                HStack(spacing: 8) {
                    Button { model.go(.briefing) } label: {
                        StIcon(name: "close", size: 16, color: .white)
                            .frame(width: 40, height: 40).liquidGlass(radius: 13, tone: .dark)
                    }.buttonStyle(.plain)
                    HStack(spacing: 9) {
                        Circle().fill(theme.bad).frame(width: 7, height: 7)
                        Text("REC").font(.mono(11, .bold)).foregroundStyle(.white)
                        Text("00:42.3").font(.mono(12, .semibold)).foregroundStyle(.white)
                        Spacer()
                        Text("OBJ · FULL · 4K").font(.mono(10)).foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 13).frame(height: 40).liquidGlass(radius: 13, tone: .dark)
                    HStack(spacing: 5) {
                        StIcon(name: "thermal", size: 13, color: .white.opacity(0.7))
                        Text("34°").font(.mono(11)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12).frame(height: 40).liquidGlass(radius: 13, tone: .dark)
                }

                // telemetry
                DarkTelemetry(items: [("LUX", "1840", nil), ("DIST", "42cm", nil),
                                      ("SHARP", "0.94", Color(hex: "#7FD9A6")), ("MOTION", "34°/s", Color(hex: "#E7B24C"))])
                    .padding(.top, 8)

                // coverage tile top-right
                HStack {
                    Spacer()
                    coverageTile.frame(width: 132)
                }
                .padding(.top, 8)

                Spacer()

                // object label
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        DLabel(text: "AI Scene · Auto-Pilot", color: Color(hex: "#9FC0FF"))
                        Text("Ceramic bust").font(.sf(15, .bold)).tracking(-0.3).foregroundStyle(.white)
                        Text("14.2 × 10.8 × 14.2 cm · conf 0.94").font(.mono(10)).foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .liquidGlass(radius: 13, tone: .dark)
                    Spacer()
                }
                .padding(.bottom, 14)

                // coaching toast
                HStack(spacing: 8) {
                    StIcon(name: "speed", size: 14, color: Color(hex: "#E7B24C"))
                    Text("Slow down · 34 → under 30°/s").font(.sf(12.5, .semibold)).foregroundStyle(.white)
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                .liquidGlass(radius: 99, tone: .dark)
                .padding(.bottom, 9)

                // shutter dock
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        DLabel(text: "Mode")
                        Text("Object").font(.sf(18, .bold)).tracking(-0.4).foregroundStyle(.white)
                        Text("FULL · 4K").font(.mono(9.5)).foregroundStyle(Color(hex: "#E7B24C"))
                    }.frame(width: 88, alignment: .leading)
                    Spacer()
                    Shutter { model.go(.review) }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        DLabel(text: "ETA · Mac")
                        Text("1:52").font(.sf(20, .bold)).tracking(-0.8).foregroundStyle(.white)
                        Text("local 6:42").font(.mono(9.5)).foregroundStyle(.white.opacity(0.5))
                    }.frame(width: 88, alignment: .trailing)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .liquidGlass(radius: 20, tone: .dark)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    private var coverageTile: some View {
        VStack(spacing: 2) {
            HStack {
                DLabel(text: "Coverage")
                Spacer()
                Text("22 SH").font(.mono(9)).foregroundStyle(.white.opacity(0.4))
            }
            CoverageSphere(pct: 72).frame(height: 104)
            HStack(alignment: .bottom) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("72").font(.sf(30, .heavy)).tracking(-1).foregroundStyle(.white)
                    Text("%").font(.sf(13, .semibold)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("16 strong").foregroundStyle(Color(hex: "#7FD9A6"))
                    Text("3 weak").foregroundStyle(Color(hex: "#E7B24C"))
                    Text("3 gap").foregroundStyle(Color(hex: "#FF8A7E"))
                }
                .font(.sf(9.5, .semibold))
            }
        }
        .padding(12)
        .liquidGlass(radius: 16, tone: .dark)
    }
}
