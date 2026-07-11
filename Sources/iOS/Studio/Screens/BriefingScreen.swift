// BriefingScreen.swift — pre-capture briefing & guidance, ported from screens/briefing.jsx
// Self-adapts on horizontal size class: compact (iPhone) → scrolling single column;
// regular (iPad) → the bespoke, non-scrolling two-column live-preview / readiness layout.

import SwiftUI

// MARK: - Data

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
    .init(id: "light", label: "Use even, diffuse lighting", status: "note", detail: "Avoid hard shadows and direct glare.", icon: "light"),
    .init(id: "reflect", label: "Watch reflective surfaces", status: "note", detail: "Glass, mirrors, and clear materials may not reconstruct well.", icon: "warning"),
    .init(id: "distance", label: "Keep a steady distance", status: "note", detail: "Keep the whole subject in frame as you move around it.", icon: "ruler"),
    .init(id: "support", label: "Keep the subject still", status: "note", detail: "A stable surface or turntable helps preserve alignment.", icon: "cube"),
    .init(id: "thermal", label: "Start with a cool device", status: "note", detail: "Long captures can slow down if the device gets warm.", icon: "thermal"),
    .init(id: "storage", label: "Leave room for source images", status: "note", detail: "Captured frames are saved to the Library for reconstruction.", icon: "download"),
]

private let GUIDES: [GuideItem] = [
    .init(title: "Move slowly", desc: "Keep angular velocity below 30 °/s. Walk a smooth orbit, not a stroll.", icon: "speed"),
    .init(title: "Three passes", desc: "Eye-level, then high, then low — 360° each. Overlap by 60%.", icon: "refresh"),
    .init(title: "Hands-free turntable", desc: "For objects under 30 cm, rotate the object — not the camera.", icon: "hand"),
    .init(title: "Avoid shiny + clear", desc: "Glass, mirrors, water absorb poorly. Mark them or skip them.", icon: "warning"),
]

// MARK: - Screen (size-class dispatcher)

struct BriefingScreen: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if hSize == .regular && !dynamicTypeSize.isAccessibilitySize {
            PadBriefingBody()
        } else {
            PhoneBriefingBody()
        }
    }
}

// MARK: - iPhone layout (scrolling single column)

private struct PhoneBriefingBody: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WizardHeader(step: 2, onBack: { model.go(.mode) }, onClose: { model.go(.library) })

                    VStack(alignment: .leading, spacing: 0) {
                        StLabel(text: "Scene briefing")
                        Text("Prepare your setup")
                            .font(.sf(28, .bold)).tracking(0).lineSpacing(1.4)
                            .foregroundStyle(theme.ink).padding(.top, 6)
                    }
                    .padding(.top, 18)

                    StCard(radius: 20, pad: 16) {
                        HStack(spacing: 16) {
                            Circle()
                                .fill(theme.accentSoft)
                                .frame(width: 58, height: 58)
                                .overlay(StIcon(name: "camera", size: 24, color: theme.accent))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Capture guidance")
                                    .font(.sf(15, .bold)).tracking(0).foregroundStyle(theme.ink)
                                Text("Review these recommendations, then choose the detail tier for this scan.")
                                    .font(.sf(12.5)).foregroundStyle(theme.text2).lineSpacing(4)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.top, 14)

                    // checklist (phone shows the first four rows only)
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
                        .font(.sf(14, .bold)).tracking(0).foregroundStyle(theme.ink)
                        .padding(.top, 18).padding(.bottom, 10)

                    // pro-tip guides (phone shows the first two only)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Array(GUIDES.prefix(2)), id: \.id) { g in GuideCard(guide: g) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomCTA {
                StButton(title: "Continue to Detail", kind: .accent, size: .lg, icon: "bolt", full: true) { model.go(.quality) }
            }
        }
    }
}

// MARK: - iPad layout (fixed two-column live preview + readiness)

private struct PadBriefingBody: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel
    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                header
                StSplitPane(ratio: 1.05 / 2.0, gap: 16) {
                    leftColumn
                } right: {
                    rightColumn
                }
            }
            .padding(24)
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                CircleIconButton(icon: "back", size: 38, action: { model.go(.mode) })
                VStack(alignment: .leading, spacing: 2) {
                    StLabel(text: "New Scan · Step 2 of 4")
                    Text("Scene briefing & guidance")
                        .font(.sf(17, .bold)).tracking(0).foregroundStyle(theme.ink)
                }
            }
            Spacer(minLength: 12)
            StStepTabs(current: 1)
            Spacer(minLength: 12)
            StButton(title: "Skip briefing", kind: .ghost, size: .sm) { model.go(.quality) }
        }
    }

    // MARK: left column — capture guidance + guides

    private var leftColumn: some View {
        VStack(spacing: 14) {
            previewFrame
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(GUIDES, id: \.id) { g in
                    GuideCard(guide: g).frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var previewFrame: some View {
        Stage(radius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                StIcon(name: "camera", size: 34, color: theme.accent)
                Text("Capture starts after detail selection.")
                    .font(.sf(22, .bold))
                    .foregroundStyle(theme.ink)
                Text("No live camera is active on this screen. The capture flow will request camera access when you continue.")
                    .font(.sf(13.5))
                    .foregroundStyle(theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .stShadow(theme.cardShadow)
    }

    // MARK: right column — readiness + checklist + actions

    private var rightColumn: some View {
        VStack(spacing: 14) {
            readinessCard
            checklistCard
            actionRow
        }
    }

    private var readinessCard: some View {
        StCard(radius: 22, pad: 20) {
            HStack(spacing: 18) {
                Circle()
                    .fill(theme.accentSoft)
                    .frame(width: 88, height: 88)
                    .overlay(StIcon(name: "check", size: 30, color: theme.accent, weight: .heavy))
                VStack(alignment: .leading, spacing: 0) {
                    StLabel(text: "Before you capture", color: theme.accentText)
                    Text("Use this as a setup guide")
                        .font(.sf(22, .bold)).tracking(0).foregroundStyle(theme.ink)
                        .padding(.top, 6)
                    Text("3DSeen checks the captured image archive after collection. This screen does not report live scene measurements.")
                        .font(.sf(13)).foregroundStyle(theme.text2).lineSpacing(5.2)
                        .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var checklistCard: some View {
        StCard(radius: 20, pad: 0) {
            VStack(spacing: 0) {
                ForEach(Array(CHECKLIST.enumerated()), id: \.element.id) { i, c in
                    CheckRow(item: c)
                    if i < CHECKLIST.count - 1 { StRule() }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 18).padding(.vertical, 4)
        }
        .frame(maxHeight: .infinity)
    }

    private var actionRow: some View {
        StButton(title: "Continue to Detail", kind: .accent, icon: "bolt", full: true) { model.go(.quality) }
        .frame(height: 44)
    }
}

// MARK: - Shared rows / cards (used by both layouts)

private struct StatusDot: View {
    @Environment(\.theme) private var theme
    let status: String
    var body: some View {
        let c = status == "pass" ? theme.good : status == "warn" ? theme.warn : theme.accent
        let bg = status == "pass" ? theme.goodSoft : status == "warn" ? theme.warnSoft : theme.accentSoft
        Circle().fill(bg).frame(width: 28, height: 28)
            .overlay(
                Group {
                    if status == "pass" {
                        StIcon(name: "check", size: 14, color: c, weight: .heavy)
                    } else if status == "warn" {
                        Text("!").font(.sf(14, .heavy)).foregroundStyle(c)
                    } else {
                        StIcon(name: "info", size: 14, color: c, weight: .heavy)
                    }
                }
            )
            .accessibilityHidden(true)
    }
}

private struct CheckRow: View {
    @Environment(\.theme) private var theme
    let item: CheckItem
    var body: some View {
        HStack(spacing: 12) {
            StatusDot(status: item.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label).font(.sf(14, .semibold)).tracking(0).foregroundStyle(theme.ink)
                Text(item.detail).font(.sf(11.5)).monospacedDigit().foregroundStyle(theme.text3)
            }
            Spacer(minLength: 0)
            StIcon(name: item.icon, size: 16, color: theme.text4).accessibilityHidden(true)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.status == "warn" ? "Warning" : "Guidance")
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
                    .accessibilityHidden(true)
                Text(guide.title).font(.sf(13.5, .bold)).tracking(0).foregroundStyle(theme.ink)
                Text(guide.desc).font(.sf(11.5)).foregroundStyle(theme.text2).lineSpacing(4.5).padding(.top, 4)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
    }
}
