// LibraryScreen.swift — Home / scan library (iPhone), ported from studio/screens/library.jsx (PhoneLibrary)

import SwiftUI
import SwiftData

struct LibraryScreen: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel
    @Query(sort: \ScanSession.creationDate, order: .reverse) private var saved: [ScanSession]
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var filter = "All"

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12),
              count: AdaptiveColumns.count(hSize, compact: 2, regular: 4))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // header
                    HStack {
                        StLabel(text: "3DSeen · 42 scans")
                        Spacer()
                        Button { model.go(.settings) } label: {
                            StIcon(name: "settings", size: 17, color: theme.text2)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(theme.fieldFill))
                        }.buttonStyle(.plain)
                    }
                    .padding(.top, 4)

                    Text("Library")
                        .font(.sf(36, .heavy)).tracking(-1.2)
                        .foregroundStyle(theme.ink)
                        .padding(.top, 6)
                    Text(saved.isEmpty
                         ? "11.4 GB on device · 2 syncing to iCloud"
                         : "\(saved.count) captured on this device · synced to iCloud")
                        .font(.sf(13.5)).foregroundStyle(theme.text2)
                        .padding(.top, 6)

                    // search
                    HStack(spacing: 10) {
                        StIcon(name: "search", size: 17, color: theme.text3)
                        Text("Search scans, tags, materials").font(.sf(14.5)).foregroundStyle(theme.text3)
                        Spacer()
                    }
                    .padding(.horizontal, 14).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 14).fill(theme.fieldFill))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.line, lineWidth: 0.5))
                    .padding(.top, 16)

                    // featured
                    FeaturedCard(scan: saved.first.map(ScanItem.init) ?? SampleData.scans[0]).padding(.top, 16)

                    // captured-on-device (live SwiftData)
                    if !saved.isEmpty {
                        HStack {
                            StLabel(text: "Captured on this device")
                            Spacer()
                            Text("\(saved.count)").font(.mono(11)).foregroundStyle(theme.text3)
                        }
                        .padding(.top, 18).padding(.bottom, 10)
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(saved) { session in
                                ScanThumb(scan: ScanItem(session)).onTapGesture { model.go(.viewer) }
                            }
                        }
                    }

                    // filters
                    FilterPills(active: $filter).padding(.top, 18).padding(.bottom, 12)

                    // sample grid
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(SampleData.scans[1..<7]) { s in
                            ScanThumb(scan: s).onTapGesture { model.go(.viewer) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
                .readableContentWidth(980)
            }

            // floating new-scan dock
            StGlass(radius: 999) {
                HStack(spacing: 4) {
                    HStack(spacing: 7) {
                        StIcon(name: "grid", size: 17, color: theme.accent)
                        Text("Library").font(.sf(14.5, .semibold)).foregroundStyle(theme.ink)
                    }
                    .padding(.horizontal, 14).frame(height: 46)
                    Button { model.go(.mode) } label: {
                        HStack(spacing: 7) {
                            StIcon(name: "scan", size: 17, color: theme.onAccent, weight: .semibold)
                            Text("New Scan").font(.sf(14.5, .semibold)).foregroundStyle(theme.onAccent)
                        }
                        .padding(.horizontal, 20).frame(height: 46)
                        .background(Capsule().fill(theme.accent))
                    }.buttonStyle(.plain)
                }
                .padding(6)
            }
            .fixedSize()
            .padding(.bottom, 28)
        }
    }
}

// MARK: - Featured card

private struct FeaturedCard: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel
    let scan: ScanItem

    var body: some View {
        StCard(radius: 22, pad: 14) {
            HStack(spacing: 14) {
                ScanThumb(scan: scan, label: false).frame(width: 92)
                VStack(alignment: .leading, spacing: 0) {
                    StLabel(text: "Just finished", color: theme.accentText)
                    Text(scan.name).font(.sf(19, .bold)).tracking(-0.6).foregroundStyle(theme.ink).padding(.top, 6)
                    Text("\(scan.tier.uppercased()) · \(scan.tris) tris · \(scan.mb) MB")
                        .font(.mono(11)).foregroundStyle(theme.text3).padding(.top, 4)
                    HStack(spacing: 8) {
                        StButton(title: "Open in 3D", kind: .accent, size: .sm, icon: "cube") { model.go(.viewer) }
                        StButton(title: "Export", kind: .secondary, size: .sm, icon: "export") { model.go(.export) }
                    }
                    .padding(.top, 10)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Filter pills

private struct FilterPills: View {
    @Environment(\.theme) private var theme
    @Binding var active: String
    private let counts: [(String, Int)] = [("All", 42), ("Object", 28), ("Space", 9), ("Landscape", 5)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(counts, id: \.0) { k, c in
                let on = k == active
                Button { active = k } label: {
                    HStack(spacing: 6) {
                        Text(k).font(.sf(13, .semibold)).tracking(-0.1)
                        Text("\(c)").font(.sf(11)).monospacedDigit().opacity(0.6)
                    }
                    .foregroundStyle(on ? theme.bg : theme.text2)
                    .padding(.horizontal, 13).padding(.vertical, 7)
                    .background(Capsule().fill(on ? theme.ink : theme.fieldFill))
                    .overlay(Capsule().strokeBorder(on ? .clear : theme.line, lineWidth: 0.5))
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}
