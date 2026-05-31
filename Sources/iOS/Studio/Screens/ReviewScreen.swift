// ReviewScreen.swift — post-capture review (iPhone), ported from screens/review.jsx (PhoneReview)

import SwiftUI

struct ReviewScreen: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel

    private func sevColor(_ s: String) -> Color { s == "high" ? theme.bad : s == "med" ? theme.warn : theme.accent }

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // header
                    HStack {
                        CircleIconButton(icon: "back") { model.go(.viewfinder) }
                        Spacer()
                        StChip(tone: .good) {
                            Circle().fill(theme.good).frame(width: 6, height: 6)
                            Text("Capture complete")
                        }
                        Spacer()
                        CircleIconButton(icon: "share") {}
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        StLabel(text: "Coverage 92% · 340 frames", color: theme.good)
                        Text("Review & retake").font(.sf(28, .heavy)).tracking(-0.9).foregroundStyle(theme.ink).padding(.top, 6)
                        Text("3 weak spots flagged. Retake them, or proceed to compute.")
                            .font(.sf(13.5)).foregroundStyle(theme.text2).padding(.top, 8)
                    }
                    .padding(.top, 18)

                    // coverage dome card
                    StCard(radius: 22, pad: 16) {
                        VStack(spacing: 4) {
                            HStack(spacing: 18) {
                                legendDot("Strong", theme.good)
                                legendDot("Weak", theme.warn)
                                legendDot("Missing", theme.bad)
                            }
                            CoverageDome(drops: SampleData.dropouts).frame(height: 240)
                        }
                    }
                    .padding(.top, 14)

                    // dropout rows
                    StCard(radius: 20, pad: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(SampleData.dropouts.enumerated()), id: \.element.id) { i, d in
                                HStack(spacing: 12) {
                                    let c = sevColor(d.severity)
                                    Circle().fill(c.opacity(0.12)).frame(width: 22, height: 22)
                                        .overlay(Text("\(i + 1)").font(.sf(11, .bold)).foregroundStyle(c))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(d.label).font(.sf(13.5, .semibold)).foregroundStyle(theme.ink)
                                        Text(d.hint).font(.sf(11)).foregroundStyle(theme.text3)
                                    }
                                    Spacer(minLength: 0)
                                    Button { model.go(.viewfinder) } label: {
                                        Text("Retake").font(.sf(12.5, .semibold)).foregroundStyle(theme.ink)
                                            .padding(.horizontal, 12).frame(height: 30)
                                            .background(Capsule().fill(theme.fieldFillHi))
                                    }.buttonStyle(.plain)
                                }
                                .padding(.vertical, 11)
                                if i < SampleData.dropouts.count - 1 { StRule() }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
                .readableContentWidth()
            }

            BottomCTA {
                HStack(spacing: 8) {
                    StButton(title: "Retake all", kind: .secondary, icon: "refresh", full: true) { model.go(.viewfinder) }
                    StButton(title: "Compute now", kind: .accent, icon: "chip", full: true) { model.go(.compute) }
                }
            }
        }
    }

    @ViewBuilder private func legendDot(_ l: String, _ c: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 8, height: 8)
            StLabel(text: l)
        }
    }
}
