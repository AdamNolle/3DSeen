// ModePickerScreen.swift — capture mode picker (iPhone), ported from screens/mode.jsx (PhoneModePicker)

import SwiftUI

struct CaptureModeInfo: Identifiable {
    let id: String
    let name: String
    let icon: String
    let tag: String
    let sub: String
    let specs: [String]
    let tint: Color
}

let STUDIO_MODES: [CaptureModeInfo] = [
    .init(id: "auto", name: "Auto-Pilot", icon: "sparkle", tag: "CoreML scene analysis",
          sub: "A vision model reads the live feed and selects the optimal mode for you.",
          specs: ["Adaptive", "Recommended", "No setup"], tint: Color(hex: "#2D68F0")),
    .init(id: "object", name: "Object", icon: "cube", tag: "Photogrammetry · ObjectCapture",
          sub: "Hi-fidelity model of a single object. RealityKit-native, LiDAR-optional.",
          specs: ["LiDAR optional", "8K textures", "4–10 min"], tint: Color(hex: "#5B7E84")),
    .init(id: "space", name: "Space", icon: "room", tag: "RoomPlan · Parametric",
          sub: "Structural blocks of rooms, walls, openings, furniture. LiDAR-required.",
          specs: ["LiDAR required", "USDZ + walls", "2–5 min"], tint: Color(hex: "#7A6244")),
    .init(id: "landscape", name: "Landscape", icon: "landscape", tag: "ARKit VIO · GPS anchored",
          sub: "Outdoor scenes where LiDAR is blinded by sun. Visual-inertial odometry.",
          specs: ["No LiDAR", "GPS anchored", "6–20 min"], tint: Color(hex: "#4C5A60")),
]

struct ModePickerScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var model: StudioModel
    @EnvironmentObject private var stateMachine: ProcessingStateMachine
    @State private var sel = "auto"
    @State private var live = false
    @State private var didPersist = false

    private var liveTone: String {
        switch liveMode {
        case .space: return "graphite"
        case .landscape: return "slate"
        default: return "bone"
        }
    }

    private var selected: CaptureModeInfo { STUDIO_MODES.first { $0.id == sel } ?? STUDIO_MODES[0] }

    /// Map the Studio mode id to a live engine capture mode.
    private var liveMode: CaptureMode {
        switch sel {
        case "space": return .space
        case "landscape": return .landscape
        default: return .object
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WizardHeader(step: 1, onBack: { model.go(.library) }, onClose: { model.go(.library) })

                    VStack(alignment: .leading, spacing: 0) {
                        StLabel(text: "Choose capture")
                        Text("What are you\nscanning today?")
                            .font(.sf(30, .heavy)).tracking(-1).foregroundStyle(theme.ink)
                            .padding(.top, 6)
                        Text("Auto-Pilot will pick for you — or choose a mode.")
                            .font(.sf(13.5)).foregroundStyle(theme.text2).padding(.top, 8)
                    }
                    .padding(.top, 18)

                    ModeTile(mode: STUDIO_MODES[0], selected: sel == "auto", big: true) { sel = "auto" }
                        .padding(.top, 18)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(STUDIO_MODES[1...]) { m in
                            ModeTile(mode: m, selected: sel == m.id, big: false) { sel = m.id }
                        }
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
                .readableContentWidth()
            }

            BottomCTA {
                VStack(spacing: 8) {
                    StButton(title: sel == "auto" ? "Start Auto-Pilot" : "Continue · \(selected.name)",
                             kind: .accent, size: .lg, icon: selected.icon, full: true) { model.go(.briefing) }
                    Button {
                        didPersist = false
                        stateMachine.send(.startCapture(liveMode))
                        live = true
                    } label: {
                        HStack(spacing: 6) {
                            StIcon(name: "camera", size: 14, color: theme.text2)
                            Text("Skip walkthrough · live capture").font(.sf(13, .semibold)).foregroundStyle(theme.text2)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
        .fullScreenCover(isPresented: $live, onDismiss: { stateMachine.send(.reset) }) {
            CaptureCoordinatorView(captureMode: liveMode)
                .environmentObject(stateMachine)
                .onReceive(stateMachine.$state) { st in
                    if case .capturing = st { return }
                    // Capture finished → persist a real ScanSession (once).
                    if case .packagingScan = st, !didPersist {
                        didPersist = true
                        let session = ScanSession(
                            captureMode: liveMode,
                            name: "\(liveMode.rawValue) Scan",
                            sizeMB: Int.random(in: 60...260),
                            tier: "Full",
                            tone: liveTone,
                            triangles: "4.2M"
                        )
                        modelContext.insert(session)
                        try? modelContext.save()
                    }
                    live = false
                }
        }
    }
}

struct ModeTile: View {
    @Environment(\.theme) private var theme
    let mode: CaptureModeInfo
    var selected: Bool
    var big: Bool
    var onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    RoundedRectangle(cornerRadius: big ? 14 : 12, style: .continuous)
                        .fill(selected ? theme.accent : theme.fieldFill)
                        .frame(width: big ? 48 : 40, height: big ? 48 : 40)
                        .overlay(StIcon(name: mode.icon, size: big ? 24 : 20, color: selected ? theme.onAccent : mode.tint))
                        .overlay(RoundedRectangle(cornerRadius: big ? 14 : 12).strokeBorder(selected ? .clear : theme.line, lineWidth: 0.5))
                    Spacer()
                    if selected { StTextChip(text: "SELECTED", tone: .accent) }
                }
                Text(mode.name).font(.sf(big ? 22 : 17, .bold)).tracking(-0.4).foregroundStyle(theme.ink)
                    .padding(.top, big ? 14 : 10)
                StLabel(text: mode.tag, color: selected ? theme.accentText : theme.text3).padding(.top, 4)
                if big {
                    Text(mode.sub).font(.sf(13)).foregroundStyle(theme.text2).lineSpacing(2).padding(.top, 8)
                    HStack(spacing: 6) {
                        ForEach(mode.specs, id: \.self) { s in StTextChip(text: s) }
                    }
                    .padding(.top, 14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(big ? 20 : 15)
            .background(RoundedRectangle(cornerRadius: big ? 22 : 18, style: .continuous).fill(selected ? theme.accentSoft : theme.card))
            .overlay(RoundedRectangle(cornerRadius: big ? 22 : 18, style: .continuous).strokeBorder(selected ? theme.accentLine : theme.line, lineWidth: selected ? 1 : 0.5))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 6)
        }
        .buttonStyle(.plain)
    }
}
