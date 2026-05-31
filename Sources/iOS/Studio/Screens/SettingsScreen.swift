// SettingsScreen.swift — settings / profile (iPhone), ported from screens/settings.jsx (PhoneSettings)

import SwiftUI

private struct SettingRowData: Identifiable {
    var id: String { label }
    let label: String
    let icon: String
    var value: String?
    var toggle: Bool?
}

private struct SettingSection: Identifiable {
    var id: String { title }
    let title: String
    let icon: String
    let rows: [SettingRowData]
}

private let SETTINGS: [SettingSection] = [
    .init(title: "Capture defaults", icon: "camera", rows: [
        .init(label: "Default mode", icon: "sparkle", value: "Auto-Pilot"),
        .init(label: "Default detail tier", icon: "layers", value: "Medium"),
        .init(label: "Audio shutter cue", icon: "bolt", toggle: true),
        .init(label: "Haptic coaching", icon: "hand", toggle: true),
    ]),
    .init(title: "Compute & handoff", icon: "chip", rows: [
        .init(label: "Auto-handoff to Mac when available", icon: "laptop", toggle: true),
        .init(label: "Thermal protection", icon: "thermal", value: "Auto-pause"),
        .init(label: "Background processing", icon: "chip", value: "Allow"),
        .init(label: "Color management", icon: "light", value: "Display P3"),
    ]),
    .init(title: "Storage", icon: "download", rows: [
        .init(label: "Keep Raw archive on device", icon: "download", value: "Latest 5"),
        .init(label: "iCloud backup", icon: "cloud", toggle: true),
        .init(label: "Smart offload", icon: "refresh", value: "> 30 days", toggle: true),
    ]),
    .init(title: "Privacy", icon: "lock", rows: [
        .init(label: "Location in scan metadata", icon: "pin", toggle: false),
        .init(label: "On-device AI only", icon: "sparkle", toggle: true),
        .init(label: "Anonymous improvement", icon: "info", toggle: false),
    ]),
]

private let SETTINGS_DEVICES: [(String, String, Bool)] = [
    ("Adam's MBP", "Wi-Fi · M4 Max", true),
    ("Studio Mini", "Wired · M2", false),
]

struct SettingsScreen: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        CircleIconButton(icon: "back") { model.go(.library) }
                        Spacer()
                        StTextChip(text: "Settings")
                        Spacer()
                        CircleIconButton(icon: "info") {}
                    }

                    // profile card
                    StCard(radius: 24, pad: 18) {
                        HStack(spacing: 14) {
                            Avatar()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Adam Nolle").font(.sf(18, .heavy)).tracking(-0.4).foregroundStyle(theme.ink)
                                Text("3DSeen STUDIO · v2.4.1").font(.mono(11)).foregroundStyle(theme.text3)
                            }
                            Spacer(minLength: 0)
                            StTextChip(text: "PRO", tone: .accent)
                        }
                    }
                    .padding(.top, 16)

                    ForEach(SETTINGS) { sec in
                        StLabel(text: sec.title).padding(.top, 18).padding(.bottom, 8).padding(.horizontal, 4)
                        SectionCard(section: sec)
                    }

                    StLabel(text: "Connected").padding(.top, 18).padding(.bottom, 8).padding(.horizontal, 4)
                    StCard(radius: 20, pad: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(SETTINGS_DEVICES.enumerated()), id: \.offset) { i, d in
                                HStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(d.2 ? theme.goodSoft : theme.fieldFill)
                                        .frame(width: 30, height: 30)
                                        .overlay(StIcon(name: "laptop", size: 16, color: d.2 ? theme.good : theme.text3))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(d.0).font(.sf(14, .semibold)).foregroundStyle(theme.ink)
                                        Text(d.1).font(.mono(10.5)).foregroundStyle(theme.text3)
                                    }
                                    Spacer(minLength: 0)
                                    if d.2 { StTextChip(text: "Active", tone: .good) }
                                }
                                .padding(.vertical, 11)
                                if i < SETTINGS_DEVICES.count - 1 { StRule() }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .readableContentWidth()
            }
        }
    }
}

// MARK: - Pieces

private struct Avatar: View {
    @Environment(\.theme) private var theme
    var size: CGFloat = 54
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [theme.accent, Color(hex: "#1B3A8C")], center: .init(x: 0.32, y: 0.28), startRadius: 0, endRadius: size * 0.9))
            .frame(width: size, height: size)
            .overlay(Text("A").font(.sf(size * 0.4, .bold)).foregroundStyle(.white))
            .shadow(color: theme.accentSoft, radius: 8, y: 2)
    }
}

private struct SectionCard: View {
    @Environment(\.theme) private var theme
    let section: SettingSection
    var body: some View {
        StCard(radius: 20, pad: 0) {
            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { i, r in
                    SettingRow(row: r)
                    if i < section.rows.count - 1 { StRule() }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

private struct SettingRow: View {
    @Environment(\.theme) private var theme
    let row: SettingRowData
    @State private var on = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.fieldFill)
                .frame(width: 30, height: 30)
                .overlay(StIcon(name: row.icon, size: 16, color: theme.text2))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.line, lineWidth: 0.5))
            Text(row.label).font(.sf(14, .medium)).tracking(-0.2).foregroundStyle(theme.ink)
            Spacer(minLength: 0)
            if row.toggle != nil {
                StToggle(on: $on)
            } else if let v = row.value {
                HStack(spacing: 6) {
                    Text(v).font(.sf(13.5)).foregroundStyle(theme.text2)
                    StIcon(name: "chev", size: 14, color: theme.text4)
                }
            }
        }
        .padding(.vertical, 11)
        .onAppear { on = row.toggle ?? false }
    }
}
