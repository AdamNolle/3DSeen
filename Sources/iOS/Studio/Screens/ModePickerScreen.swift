// ModePickerScreen.swift — capture mode picker, ported from screens/mode.jsx.
// Self-adapting: PhoneModePicker (compact) + bespoke PadModePicker (regular) chosen via the
// horizontal size class, per docs/design-spec/mode.md (Phone + Pad).

import SwiftUI
import AVFoundation
import ARKit
import RoomPlan

// MARK: - Data

struct CaptureModeInfo: Identifiable {
    let id: String
    let name: String
    let icon: String
    let tag: String
    let sub: String
    let specs: [String]
    let tint: Color

    var captureMode: CaptureMode {
        switch id {
        case "auto": return .autoPilot
        case "space": return .space
        case "landscape": return .landscape
        default: return .object
        }
    }
}

let STUDIO_MODES: [CaptureModeInfo] = [
    .init(id: "auto", name: "Auto-Pilot", icon: "sparkle", tag: "Vision scene classification",
          sub: "A vision model reads the live feed and selects the optimal mode for you.",
          specs: ["Adaptive", "Recommended", "No setup"], tint: Color(hex: "#2D68F0")),
    .init(id: "object", name: "Object", icon: "cube", tag: "Photogrammetry · ObjectCapture",
          sub: "Image capture for a single object. Reconstruct on this device or a connected Mac.",
          specs: ["Camera", "Image archive", "LiDAR optional"], tint: Color(hex: "#5B7E84")),
    .init(id: "space", name: "Space", icon: "room", tag: "RoomPlan · Parametric",
          sub: "Structural blocks of rooms, walls, openings, furniture. LiDAR-required.",
          specs: ["LiDAR", "USDZ", "Walls + openings"], tint: Color(hex: "#7A6244")),
    .init(id: "landscape", name: "Landscape", icon: "landscape", tag: "ARKit VIO · World tracking",
          sub: "Outdoor image capture using ARKit visual-inertial world tracking.",
          specs: ["VIO", "JPEG archive", "World tracking"], tint: Color(hex: "#4C5A60")),
]

// MARK: - Screen

enum CaptureAvailability {
    struct Status: Equatable {
        let isAvailable: Bool
        let message: String?
    }

    static func status(for mode: CaptureMode) -> Status {
        #if targetEnvironment(simulator)
        return Status(isAvailable: false, message: hardwareRequirement(for: mode))
        #else
        guard AVCaptureDevice.default(for: .video) != nil else {
            return Status(isAvailable: false, message: "\(mode.rawValue) capture requires a camera-equipped iPhone or iPad.")
        }

        switch mode {
        case .space where !RoomCaptureSession.isSupported:
            return Status(isAvailable: false, message: hardwareRequirement(for: mode))
        case .landscape where !ARWorldTrackingConfiguration.isSupported:
            return Status(isAvailable: false, message: hardwareRequirement(for: mode))
        default:
            break
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            return Status(
                isAvailable: false,
                message: "Camera access is off. Allow 3DSeen to use the camera in Settings before starting a scan."
            )
        case .notDetermined:
            return Status(isAvailable: true, message: "3DSeen will ask for camera access when you continue.")
        case .authorized:
            return Status(isAvailable: true, message: nil)
        @unknown default:
            return Status(isAvailable: false, message: "Camera availability could not be determined on this device.")
        }
        #endif
    }

    private static func hardwareRequirement(for mode: CaptureMode) -> String {
        switch mode {
        case .space:
            return "Space capture requires a LiDAR-equipped iPhone or iPad."
        case .landscape:
            return "Landscape capture requires AR world tracking on a physical iPhone or iPad."
        case .object:
            return "Object capture requires a physical iPhone or iPad with a camera."
        case .autoPilot:
            return "Auto-Pilot capture requires a physical iPhone or iPad with a camera."
        }
    }
}

struct ModePickerScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var model: StudioModel

    private var sel: Binding<String> {
        Binding(get: { model.selectedCaptureModeID }, set: { model.selectedCaptureModeID = $0 })
    }

    private var selected: CaptureModeInfo { STUDIO_MODES.first { $0.id == sel.wrappedValue } ?? STUDIO_MODES[0] }

    /// Map the Studio mode id to a live engine capture mode.
    private var liveMode: CaptureMode {
        selected.captureMode
    }

    private var captureAvailability: CaptureAvailability.Status {
        CaptureAvailability.status(for: liveMode)
    }

    var body: some View {
        Group {
            if hSize == .regular && !dynamicTypeSize.isAccessibilitySize {
                PadModePicker(sel: sel,
                              onBack: { model.go(.library) },
                              onClose: { model.go(.library) },
                              onContinue: { model.go(.briefing) })
            } else {
                phoneBody
            }
        }
    }

    // MARK: Phone (compact)

    private var phoneBody: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            ScrollView { phoneScroll }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomCTA {
                StButton(title: sel.wrappedValue == "auto" ? "Continue · Auto-Pilot" : "Continue · \(selected.name)",
                         kind: .accent, size: .lg, icon: selected.icon, full: true,
                         action: { model.go(.briefing) })
            }
        }
    }

    private var phoneScroll: some View {
        VStack(alignment: .leading, spacing: 0) {
            phoneNav
            phoneTitle.padding(.top, 18)
            ModeTile(mode: STUDIO_MODES[0], selected: sel.wrappedValue == "auto", big: true) { sel.wrappedValue = "auto" }
                .padding(.top, 18)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                ForEach(STUDIO_MODES[1...], id: \.id) { m in
                    ModeTile(mode: m, selected: sel.wrappedValue == m.id, big: false) { sel.wrappedValue = m.id }
                }
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    private var phoneNav: some View {
        HStack {
            ModeCircleButton(icon: "back", diameter: 36, glyph: 17, label: "Back") { model.go(.library) }
            Spacer()
            StTextChip(text: "Step 1 of 4")
            Spacer()
            ModeCircleButton(icon: "close", diameter: 36, glyph: 16, label: "Close") { model.go(.library) }
        }
    }

    private var phoneTitle: some View {
        VStack(alignment: .leading, spacing: 0) {
            StLabel(text: "Choose capture")
            // Spec H1: hard line break at lineHeight 1.05. SwiftUI `lineSpacing` cannot tighten
            // below the font's natural leading, so a tight negative VStack gap approximates it.
            VStack(alignment: .leading, spacing: -4) {
                Text("What are you")
                Text("scanning today?")
            }
            .font(.sf(30, .bold)).tracking(0).foregroundStyle(theme.ink)
            .padding(.top, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("What are you scanning today?")
            Text("Auto-Pilot will pick for you — or choose a mode.")
                .font(.sf(13.5)).foregroundStyle(theme.text2).padding(.top, 8)
            CaptureAvailabilityNotice(status: captureAvailability)
                .padding(.top, 12)
        }
    }

}

// MARK: - iPad layout (regular)

/// Bespoke `PadModePicker` from mode.jsx: a single non-scrolling column — header (title stack +
/// step tabs), a marketing hero with a live-scene card, all four modes as equal-height big tiles
/// (Auto 1.3× wide), and a device/thermal/storage status footer with an always-on CTA.
private struct PadModePicker: View {
    @Environment(\.theme) private var theme
    @Binding var sel: String
    var onBack: () -> Void
    var onClose: () -> Void
    var onContinue: () -> Void

    private var selected: CaptureModeInfo { STUDIO_MODES.first { $0.id == sel } ?? STUDIO_MODES[0] }

    private var selectedMode: CaptureMode {
        selected.captureMode
    }

    private var captureAvailability: CaptureAvailability.Status {
        CaptureAvailability.status(for: selectedMode)
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                hero.padding(.top, 28).padding(.bottom, 22)
                grid.frame(maxWidth: .infinity, maxHeight: .infinity)
                footer.padding(.top, 20)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                ModeCircleButton(icon: "back", diameter: 38, glyph: 17, label: "Back", action: onBack)
                VStack(alignment: .leading, spacing: 2) {
                    StLabel(text: "New Scan · Step 1 of 4")
                    Text("Choose capture mode")
                        .font(.sf(17, .bold)).tracking(0).foregroundStyle(theme.ink)
                }
            }
            Spacer()
            StStepTabs(current: 0)
            Spacer()
            ModeCircleButton(icon: "close", diameter: 38, glyph: 16, label: "Close", action: onClose)
        }
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                StLabel(text: "3DSeen · Capture engine", color: theme.accentText)
                Text("What are you scanning?")
                    .font(.sf(48, .bold)).tracking(0).foregroundStyle(theme.ink)
                    .padding(.top, 8)
                Text(Self.heroBody)
                    .font(.sf(15)).foregroundStyle(theme.text2)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.top, 12)
                CaptureAvailabilityNotice(status: captureAvailability)
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            selectedModeCard
        }
    }

    private static let heroBody =
        "Auto-Pilot uses Vision scene classification to read the camera feed and pick the optimal capture "
        + "mode. Or pin a specific mode for full manual control."

    private var selectedModeCard: some View {
        StCard(radius: 18, pad: 14) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected.tint.opacity(0.16))
                    .frame(width: 56, height: 56)
                    .overlay(StIcon(name: selected.icon, size: 24, color: selected.tint))
                VStack(alignment: .leading, spacing: 0) {
                    StLabel(text: "Selected capture")
                    Text(selected.name)
                        .font(.sf(14, .semibold)).foregroundStyle(theme.ink).padding(.top, 3)
                    Text(selected.tag)
                        .font(.mono(10.5)).foregroundStyle(theme.text3).padding(.top, 2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: 280)
    }

    private var grid: some View {
        GeometryReader { geo in
            let gap: CGFloat = 14
            let unit = max(0, (geo.size.width - gap * 3) / 4.3)   // 1.3 + 1 + 1 + 1 column weights
            HStack(spacing: gap) {
                ModeTile(mode: STUDIO_MODES[0], selected: sel == "auto", big: true, fillHeight: true) {
                    sel = "auto"
                }
                .frame(width: unit * 1.3)
                ForEach(STUDIO_MODES[1...], id: \.id) { m in
                    ModeTile(mode: m, selected: sel == m.id, big: true, fillHeight: true) { sel = m.id }
                        .frame(width: unit)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                StLabel(text: "Capture availability", color: captureAvailability.isAvailable ? theme.good : theme.warn)
                Text(captureAvailability.message ?? "This capture engine is available on this device.")
                    .font(.sf(12.5))
                    .foregroundStyle(theme.text2)
                    .lineLimit(2)
            }
            .frame(maxWidth: 430, alignment: .leading)
            Spacer()
            StButton(title: "Continue with \(selected.name)", kind: .accent, size: .lg,
                     icon: selected.icon, action: onContinue)
        }
    }
}

private struct CaptureAvailabilityNotice: View {
    @Environment(\.theme) private var theme
    let status: CaptureAvailability.Status

    var body: some View {
        if let message = status.message {
            StGlass(radius: 14) {
                HStack(alignment: .top, spacing: 9) {
                    StIcon(name: status.isAvailable ? "info" : "warning", size: 14,
                           color: status.isAvailable ? theme.accentText : theme.warn)
                        .padding(.top, 1)
                    Text(message)
                        .font(.sf(12.5, .medium))
                        .foregroundStyle(theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)
        }
    }
}

// MARK: - Mode tile

struct ModeTile: View {
    @Environment(\.theme) private var theme
    let mode: CaptureModeInfo
    var selected: Bool
    var big: Bool
    /// When the tile shares a fixed-height row (iPad grid), fill the height so the spec chips
    /// bottom-align via the trailing spacer. Phone tiles stay auto-height.
    var fillHeight: Bool = false
    var onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    iconChip
                    Spacer()
                    if selected { ModeSelectedChip() }
                }
                Text(mode.name).font(.sf(big ? 22 : 17, .bold)).tracking(0)
                    .foregroundStyle(theme.ink).padding(.top, big ? 14 : 10)
                StLabel(text: mode.tag, color: selected ? theme.accentText : theme.text3)
                    .padding(.top, 4)
                if big {
                    Text(mode.sub).font(.sf(13)).foregroundStyle(theme.text2)
                        .lineSpacing(2).padding(.top, 8)
                    Spacer(minLength: 0)                       // marginTop:auto — push chips down
                    Group {
                        if fillHeight {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(mode.specs, id: \.self) { s in ModeSpecChip(text: s) }
                            }
                        } else {
                            HStack(spacing: 6) {
                                ForEach(mode.specs, id: \.self) { s in ModeSpecChip(text: s) }
                            }
                        }
                    }
                    .padding(.top, 14)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
            .padding(big ? 20 : 15)
            .background(RoundedRectangle(cornerRadius: big ? 22 : 18, style: .continuous)
                .fill(selected ? theme.accentSoft : theme.card))
            .overlay(RoundedRectangle(cornerRadius: big ? 22 : 18, style: .continuous)
                .strokeBorder(selected ? theme.accentLine : theme.line, lineWidth: selected ? 1 : 0.5))
            .stShadow(theme.cardShadow)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.name). \(mode.tag)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var iconChip: some View {
        RoundedRectangle(cornerRadius: big ? 14 : 12, style: .continuous)
            .fill(selected ? theme.accent : theme.fieldFill)
            .frame(width: big ? 48 : 40, height: big ? 48 : 40)
            .overlay(StIcon(name: mode.icon, size: big ? 24 : 20,
                            color: selected ? theme.onAccent : mode.tint))
            .overlay(RoundedRectangle(cornerRadius: big ? 14 : 12)
                .strokeBorder(selected ? .clear : theme.line, lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

// MARK: - Local chrome

/// Circle nav button with an exact glyph size (spec: back 17, close 16) — the shared
/// `CircleIconButton` hardcodes 17, so the wizard nav row is built locally for fidelity.
private struct ModeCircleButton: View {
    @Environment(\.theme) private var theme
    var icon: String
    var diameter: CGFloat
    var glyph: CGFloat
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            StIcon(name: icon, size: glyph, color: theme.text2)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(theme.fieldFill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// `Chip tone="accent"` SELECTED badge — spec fontSize 9 (smaller than the shared StChip's 12).
private struct ModeSelectedChip: View {
    @Environment(\.theme) private var theme
    var body: some View {
        Text("SELECTED")
            .font(.sf(9, .semibold)).tracking(0).foregroundStyle(theme.accentText)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(theme.accentSoft))
            .overlay(Capsule().strokeBorder(theme.accentLine, lineWidth: 0.5))
            .accessibilityHidden(true)   // selection is announced via the tile's `.isSelected` trait
    }
}

/// `Chip tone="neutral"` big-tile spec chip — spec fontSize 11 (vs the shared StChip's 12).
private struct ModeSpecChip: View {
    @Environment(\.theme) private var theme
    var text: String
    var body: some View {
        Text(text)
            .font(.sf(11, .semibold)).tracking(0).foregroundStyle(theme.text2)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(theme.fieldFill))
            .overlay(Capsule().strokeBorder(theme.line, lineWidth: 0.5))
    }
}

/// Pad footer status pair: mono overline key over a 13.5/600 ink value.
private struct ModeStatusPair: View {
    @Environment(\.theme) private var theme
    var k: String
    var v: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StLabel(text: k)
            Text(v).font(.sf(13.5, .semibold)).foregroundStyle(theme.ink).padding(.top, 3)
        }
    }
}
