// BriefingScreen.swift — pre-capture briefing & guidance (iPhone), ported from screens/briefing.jsx

import SwiftUI

private struct CheckItem: Identifiable {
    let id: String
    let label: String
    let status: String   // pass / warn / bad
    let detail: String
    let icon: String
}

private struct GuideItem: Identifiable {
    var id: String { title }
    let title: String
    let desc: String
    let icon: String
}

private let CHECKLIST: [CheckItem] = [
    .init(id: "light", label: "Even, diffuse lighting", status: "pass", detail: "1842 lux measured", icon: "light"),
    .init(id: "reflect", label: "Reflective surfaces detected", status: "warn", detail: "2 glossy regions — consider polarizer", icon: "warning"),
    .init(id: "distance", label: "Distance to subject", status: "pass", detail: "42 cm · in range", icon: "ruler"),
    .init(id: "support", label: "Stable surface", status: "pass", detail: "Turntable detected", icon: "cube"),
    .init(id: "thermal", label: "Device thermal", status: "pass", detail: "Nominal · 31 °C", icon: "thermal"),
    .init(id: "storage", label: "Storage available", status: "pass", detail: "244 GB free · ~3.4 GB needed", icon: "download"),
]

private let GUIDES: [GuideItem] = [
    .init(title: "Move slowly", desc: "Keep angular velocity below 30 °/s. Walk a smooth orbit, not a stroll.", icon: "speed"),
    .init(title: "Three passes", desc: "Eye-level, then high, then low — 360° each. Overlap by 60%.", icon: "refresh"),
    .init(title: "Hands-free turntable", desc: "For objects under 30 cm, rotate the object — not the camera.", icon: "hand"),
    .init(title: "Avoid shiny + clear", desc: "Glass, mirrors, water absorb poorly. Mark them or skip them.", icon: "warning"),
]

struct BriefingScreen: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WizardHeader(step: 2, onBack: { model.go(.mode) }, onClose: { model.go(.library) })

                    VStack(alignment: .leading, spacing: 0) {
                        StLabel(text: "Scene briefing")
                        Text("You're ready in 5 of 6")
                            .font(.sf(28, .heavy)).tracking(-0.9).foregroundStyle(theme.ink).padding(.top, 6)
                    }
                    .padding(.top, 18)

                    // readiness ring card
                    StCard(radius: 20, pad: 16) {
                        HStack(spacing: 16) {
                            StRing(value: 0.83, size: 74, color: theme.good, label: "83")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Scan-readiness: Excellent").font(.sf(15, .bold)).tracking(-0.3).foregroundStyle(theme.ink)
                                Text("Resolve the reflection warning to reach 100.").font(.sf(12.5)).foregroundStyle(theme.text2)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.top, 14)

                    // checklist
                    StCard(radius: 20, pad: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(CHECKLIST.prefix(4).enumerated()), id: \.element.id) { i, c in
                                CheckRow(item: c)
                                if i < 3 { StRule() }
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 4)
                    }
                    .padding(.top, 12)

                    Text("Pro tips for this scene")
                        .font(.sf(14, .bold)).tracking(-0.2).foregroundStyle(theme.ink)
                        .padding(.top, 18).padding(.bottom, 10)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(GUIDES.prefix(2)) { g in GuideCard(guide: g) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
                .readableContentWidth()
            }

            BottomCTA {
                StButton(title: "Continue to Detail", kind: .accent, size: .lg, icon: "bolt", full: true) { model.go(.quality) }
            }
        }
    }

    private struct CheckRow: View {
        @Environment(\.theme) private var theme
        let item: CheckItem
        var body: some View {
            HStack(spacing: 12) {
                StatusDot(status: item.status)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label).font(.sf(14, .semibold)).tracking(-0.2).foregroundStyle(theme.ink)
                    Text(item.detail).font(.sf(11.5)).foregroundStyle(theme.text3)
                }
                Spacer(minLength: 0)
                StIcon(name: item.icon, size: 16, color: theme.text4)
            }
            .padding(.vertical, 11)
        }
    }

    private struct StatusDot: View {
        @Environment(\.theme) private var theme
        let status: String
        var body: some View {
            let c = status == "pass" ? theme.good : status == "warn" ? theme.warn : theme.bad
            let bg = status == "pass" ? theme.goodSoft : status == "warn" ? theme.warnSoft : theme.badSoft
            Circle().fill(bg).frame(width: 28, height: 28)
                .overlay(Group {
                    if status == "pass" { StIcon(name: "check", size: 14, color: c, weight: .heavy) } else { Text("!").font(.sf(14, .heavy)).foregroundStyle(c) }
                })
        }
    }

    private struct GuideCard: View {
        @Environment(\.theme) private var theme
        let guide: GuideItem
        var body: some View {
            StCard(radius: 16, pad: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.accentSoft)
                        .frame(width: 32, height: 32)
                        .overlay(StIcon(name: guide.icon, size: 17, color: theme.accent))
                        .padding(.bottom, 10)
                    Text(guide.title).font(.sf(13.5, .bold)).tracking(-0.2).foregroundStyle(theme.ink)
                    Text(guide.desc).font(.sf(11.5)).foregroundStyle(theme.text2).lineSpacing(1.5).padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
