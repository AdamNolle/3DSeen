// LibraryScreen.swift — Home / scan library, ported from studio/screens/library.jsx.
// Self-adapts on horizontal size class: compact (iPhone) → `PhoneLibrary`; regular (iPad) →
// a bespoke split (`PadLibrary`): LibrarySidebar + scrolling main with inline search + New Scan,
// a big Featured card, and a multi-column Recent grid. All library facts are derived from live
// SwiftData sessions; the empty state stays empty until a real capture exists.

import SwiftUI
import SwiftData

struct LibraryScreen: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \ScanSession.creationDate, order: .reverse) private var saved: [ScanSession]
    @State private var filter = "All"
    @State private var query = ""

    var body: some View {
        if hSize == .regular && !dynamicTypeSize.isAccessibilitySize {
            PadLibrary(saved: saved, filter: $filter, query: $query)
        } else {
            PhoneLibrary(saved: saved, filter: $filter, query: $query)
        }
    }
}

// MARK: - Library data (single source of truth: live SwiftData)

private enum LibraryData {
    /// The backing scan list contains only persisted capture sessions.
    static func source(_ saved: [ScanSession]) -> [ScanItem] {
        saved.map(ScanItem.init)
    }

    /// The hero scan — the most recent live capture.
    static func featured(_ saved: [ScanSession]) -> ScanItem? {
        source(saved).first
    }

    static func summary(_ saved: [ScanSession]) -> ScanLibrarySummary {
        ScanLibrarySummary(sessions: saved)
    }

    /// The Recent grid: everything after the featured scan, filtered by the active mode pill and
    /// the search query. `limit` caps the unfiltered phone grid to the spec's `slice(1, 7)`.
    static func grid(_ saved: [ScanSession], filter: String, query: String, limit: Int?) -> [ScanItem] {
        let rest = Array(source(saved).dropFirst())
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = rest.filter { item in
            let modeOK = filter == "All" || item.mode == filter
            guard modeOK else { return false }
            guard !q.isEmpty else { return true }
            return item.name.localizedCaseInsensitiveContains(q)
                || item.mode.localizedCaseInsensitiveContains(q)
                || item.tier.localizedCaseInsensitiveContains(q)
                || item.tone.localizedCaseInsensitiveContains(q)
        }
        if let limit, q.isEmpty, filter == "All" {
            return Array(result.prefix(limit))
        }
        return result
    }
}

// MARK: - iPhone (compact)

private struct PhoneLibrary: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel
    @EnvironmentObject private var settings: SettingsStore
    let saved: [ScanSession]
    @Binding var filter: String
    @Binding var query: String

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private var featured: ScanItem? { LibraryData.featured(saved) }
    private var items: [ScanItem] { LibraryData.grid(saved, filter: filter, query: query, limit: 6) }
    private var summary: ScanLibrarySummary { LibraryData.summary(saved) }

    private var storageSubtitle: String {
        guard summary.pendingComputeCount > 0 else { return "\(summary.storageText) on device" }
        return "\(summary.storageText) on device · \(summary.pendingComputeCount) awaiting compute"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Text("Library")
                        .font(.sf(36, .bold)).tracking(0)
                        .foregroundStyle(theme.ink)
                        .padding(.top, 6)
                    Text(storageSubtitle)
                        .font(.sf(13.5)).foregroundStyle(theme.text2)
                        .padding(.top, 6)

                    LibrarySearchField(query: $query, placeholder: "Search scans, tags, materials")
                        .padding(.top, 16)

                    if let featured {
                        FeaturedCard(scan: featured).padding(.top, 16)
                    } else {
                        EmptyLibraryState().padding(.top, 16)
                    }

                    FilterPills(active: $filter, scans: items).padding(.top, 18).padding(.bottom, 12)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items, id: \.id) { s in
                            ScanThumbButton(scan: s)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }

            newScanDock
        }
    }

    private var header: some View {
        HStack {
            StLabel(text: "3DSeen · \(saved.count) scans")
            Spacer()
            Button { model.go(.settings) } label: {
                StIcon(name: "settings", size: 18, color: theme.text2)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(theme.fieldFill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.top, 4)
    }

    // Floating centered "New Scan" dock (spec §Phone step 8), pinned above the scroll.
    private var newScanDock: some View {
        StGlass(radius: 999) {
            StButton(title: "New Scan", kind: .accent, size: .lg, icon: "scan") { model.beginNewScan(using: settings) }
                .padding(6)
        }
        .fixedSize()
        .padding(.bottom, 28)
        // The functional search field raises the keyboard; keep the pinned dock anchored to the
        // safe-area bottom instead of letting keyboard avoidance push it up.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

// MARK: - iPad (regular) — bespoke sidebar + main split

private struct PadLibrary: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel
    @EnvironmentObject private var settings: SettingsStore
    let saved: [ScanSession]
    @Binding var filter: String
    @Binding var query: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 5)
    private var featured: ScanItem? { LibraryData.featured(saved) }
    private var items: [ScanItem] { LibraryData.grid(saved, filter: filter, query: query, limit: nil) }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            HStack(alignment: .top, spacing: 22) {
                LibrarySidebar(saved: saved, filter: $filter)
                    .frame(width: 248)
                    .frame(maxHeight: .infinity)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        searchRow
                        if let featured {
                            FeaturedCard(scan: featured, big: true).padding(.top, 18)
                        } else {
                            EmptyLibraryState(big: true).padding(.top, 18)
                        }
                        recentHeader
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(items, id: \.id) { s in
                                ScanThumbButton(scan: s)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .padding(22)
        }
    }

    private var searchRow: some View {
        HStack(alignment: .center, spacing: 12) {
            LibrarySearchField(query: $query,
                               placeholder: "Search scans, tags, materials…",
                               height: 46, iconSize: 18)
            StButton(title: "New Scan", kind: .accent, icon: "scan") { model.beginNewScan(using: settings) }
        }
    }

    private var recentHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Recent")
                .font(.sf(20, .bold)).tracking(0)
                .foregroundStyle(theme.ink)
            Spacer()
            FilterPills(active: $filter, scans: items, fill: false)
        }
        .padding(.top, 24).padding(.bottom, 12)
    }
}

// MARK: - Shared sidebar (Pad) — content categories + Collections + storage footer

private struct SidebarNavRow {
    let icon: String
    let title: String
    let key: String
    let count: Int
}

private struct LibrarySidebar: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel
    let saved: [ScanSession]
    @Binding var filter: String

    private var summary: ScanLibrarySummary { LibraryData.summary(saved) }
    private var nav: [SidebarNavRow] {
        [
            SidebarNavRow(icon: "grid", title: "All Scans", key: "All", count: summary.scanCount),
            SidebarNavRow(icon: "cube", title: "Objects", key: "Object", count: summary.objectCount),
            SidebarNavRow(icon: "room", title: "Spaces", key: "Space", count: summary.spaceCount),
            SidebarNavRow(icon: "landscape", title: "Landscapes", key: "Landscape", count: summary.landscapeCount),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            logoHeader
            ForEach(nav, id: \.key) { row in
                navButton(row)
            }
            Spacer(minLength: 0)
            footer
        }
    }

    private var logoHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.accent)
                StIcon(name: "scan", size: 18, color: theme.onAccent, weight: .semibold)
            }
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("3DSeen").font(.sf(15, .bold)).tracking(0).foregroundStyle(theme.ink)
                Text("v2.4 · STUDIO").font(.mono(9.5)).foregroundStyle(theme.text3)
            }
        }
        .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 12)
    }

    private func navButton(_ row: SidebarNavRow) -> some View {
        let on = filter == row.key
        return Button { filter = row.key } label: {
            HStack(spacing: 11) {
                StIcon(name: row.icon, size: 17, color: on ? theme.ink : theme.text2)
                Text(row.title)
                    .font(.sf(14, on ? .semibold : .medium))
                    .foregroundStyle(on ? theme.ink : theme.text2)
                Spacer(minLength: 0)
                Text("\(row.count)").font(.mono(11)).foregroundStyle(theme.text3)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(on ? theme.fieldFillHi : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(StPressStyle())
        .accessibilityLabel("\(row.title), \(row.count) scans")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // Footer reports persisted scan storage, rather than a fabricated device-capacity estimate.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    StLabel(text: "On device")
                    Spacer()
                    Text(summary.storageText).font(.mono(10)).foregroundStyle(theme.text3)
                }
                Text("\(summary.scanCount) saved scans")
                    .font(.sf(12.5)).foregroundStyle(theme.text2)
            }
            .padding(.horizontal, 8)

            Button { model.go(.settings) } label: {
                HStack(spacing: 11) {
                    StIcon(name: "settings", size: 17, color: theme.text2)
                    Text("Settings").font(.sf(14, .medium)).foregroundStyle(theme.text2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(StPressStyle())
            .accessibilityLabel("Settings")
        }
        .padding(.top, 12)
    }
}

// MARK: - Search field (real TextField that drives the grid filter)

private struct LibrarySearchField: View {
    @Environment(\.theme) private var theme
    @Binding var query: String
    var placeholder: String
    var height: CGFloat = 44
    var iconSize: CGFloat = 17

    var body: some View {
        HStack(spacing: 10) {
            StIcon(name: "search", size: iconSize, color: theme.text3)
            TextField("", text: $query,
                      prompt: Text(placeholder).foregroundStyle(theme.text3))
                .font(.sf(14.5))
                .foregroundStyle(theme.ink)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityLabel("Search scans")
            if !query.isEmpty {
                Button { query = "" } label: {
                    StIcon(name: "close", size: 13, color: theme.text3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.line, lineWidth: 0.5))
    }
}

// MARK: - Tappable scan thumbnail

private struct ScanThumbButton: View {
    @EnvironmentObject private var model: StudioModel
    let scan: ScanItem

    var body: some View {
        Button {
            if let id = UUID(uuidString: scan.id) {
                model.activeScanID = id
            }
            model.go(.viewer)
        } label: {
            ScanThumb(scan: scan)
        }
        .buttonStyle(StPressStyle())
        .accessibilityLabel("Open \(scan.name)")
    }
}

// MARK: - Featured card (compact + `big` for iPad)

private struct EmptyLibraryState: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel
    @EnvironmentObject private var settings: SettingsStore
    var big: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: big ? 18 : 12) {
            StIcon(name: "scan", size: big ? 34 : 26, color: theme.accentText)
                .frame(width: big ? 62 : 50, height: big ? 62 : 50)
                .liquidGlass(radius: 18)

            VStack(alignment: .leading, spacing: 6) {
                Text("No scans yet")
                    .font(.sf(big ? 28 : 20, .bold))
                    .foregroundStyle(theme.ink)
                Text("Create a scan to fill your library.")
                    .font(.sf(big ? 15 : 13.5))
                    .foregroundStyle(theme.text2)
            }

            StButton(title: "New Scan", kind: .accent, size: big ? .lg : .sm, icon: "scan") {
                model.beginNewScan(using: settings)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(big ? 26 : 18)
        .background(theme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(theme.line.opacity(0.65), lineWidth: 1)
        )
    }
}

private struct FeaturedCard: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: StudioModel
    let scan: ScanItem
    var big: Bool = false

    private func selectScan() {
        if let id = UUID(uuidString: scan.id) {
            model.activeScanID = id
        }
    }

    var body: some View {
        StCard(radius: big ? 24 : 22, pad: big ? 16 : 14, elevated: big) {
            if big { bigBody } else { compactBody }
        }
    }

    private var compactBody: some View {
        HStack(spacing: 14) {
            ScanThumb(scan: scan, label: false).frame(width: 92)
            VStack(alignment: .leading, spacing: 0) {
                StLabel(text: "Just finished", color: theme.accentText)
                Text(scan.name)
                    .font(.sf(19, .bold)).tracking(0)
                    .foregroundStyle(theme.ink).padding(.top, 6)
                Text("\(scan.tier.uppercased()) · \(scan.tris) tris · \(scan.mb) MB")
                    .font(.mono(11)).foregroundStyle(theme.text3).padding(.top, 4)
                HStack(spacing: 8) {
                    StButton(title: "Open in 3D", kind: .accent, size: .sm, icon: "cube") { selectScan(); model.go(.viewer) }
                    StButton(title: "Export", kind: .secondary, size: .sm, icon: "export") { selectScan(); model.go(.export) }
                }
                .padding(.top, 10)
            }
            Spacer(minLength: 0)
        }
    }

    private var bigBody: some View {
        HStack(alignment: .top, spacing: 18) {
            stage
            VStack(alignment: .leading, spacing: 0) {
                StLabel(text: "Featured", color: theme.accentText)
                Text(scan.name)
                    .font(.sf(27, .bold)).tracking(0)
                    .foregroundStyle(theme.ink).padding(.top, 8)
                Text("\(scan.mode) · captured \(scan.date)")
                    .font(.sf(14)).foregroundStyle(theme.text2).padding(.top, 4)
                HStack(spacing: 22) {
                    StStat(k: "Triangles", v: scan.tris, size: .sm)
                    StStat(k: "Size", v: "\(scan.mb)", unit: "MB", size: .sm)
                    StStat(k: "Tier", v: scan.tier, size: .sm)
                }
                .padding(.top, 18)
                HStack(spacing: 10) {
                    StButton(title: "Open in 3D", kind: .accent, icon: "cube") { selectScan(); model.go(.viewer) }
                    StButton(title: "Export", kind: .secondary, icon: "export") { selectScan(); model.go(.export) }
                }
                .padding(.top, 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stage: some View {
        Stage(radius: 18) {
            VStack(spacing: 10) {
                StIcon(name: "cube", size: 38, color: theme.accentText)
                Text("Open in 3D to inspect")
                    .font(.sf(13, .semibold))
                    .foregroundStyle(theme.text2)
                Text(scan.name)
                    .font(.mono(10.5))
                    .foregroundStyle(theme.text3)
                    .lineLimit(1)
            }
            .padding(20)
        }
        .frame(width: 300, height: 248)
        .accessibilityLabel("Model preview is available in the viewer")
    }
}

// MARK: - Filter pills (drive the grid by mode)

private struct FilterPills: View {
    @Environment(\.theme) private var theme
    @Binding var active: String
    let scans: [ScanItem]
    /// When true (phone) a trailing spacer left-aligns the row; when false (iPad Recent header)
    /// the pills hug their content so they sit at the right edge.
    var fill: Bool = true
    private var counts: [(String, Int)] {
        [
            ("All", scans.count),
            ("Object", scans.filter { $0.mode == "Object" }.count),
            ("Space", scans.filter { $0.mode == "Space" }.count),
            ("Landscape", scans.filter { $0.mode == "Landscape" }.count)
        ]
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(counts, id: \.0) { k, c in
                    pill(k, c)
                }
                if fill { Spacer(minLength: 0) }
            }
        }
        .scrollClipDisabled()
    }

    private func pill(_ k: String, _ c: Int) -> some View {
        let on = k == active
        return Button { active = k } label: {
            HStack(spacing: 6) {
                Text(k).font(.sf(13, .semibold)).lineLimit(1)
                Text("\(c)").font(.mono(11)).opacity(0.6)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(on ? theme.bg : theme.text2)
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(Capsule().fill(on ? theme.ink : theme.fieldFill))
            .overlay(Capsule().strokeBorder(on ? .clear : theme.line, lineWidth: 0.5))
        }
        .buttonStyle(StPressStyle())
        .accessibilityLabel("\(k), \(c) scans")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
