import SwiftUI

/// The desktop scan library. Its contents are durable results retained by `ComputeCoordinator`;
/// there are no sample scans, fabricated category counts, or placeholder storage totals here.
struct MacLibraryPane: View {
    @Environment(\.theme) private var theme
    @Binding var section: MacSection
    @ObservedObject var settings: SettingsStore
    @ObservedObject var compute: ComputeCoordinator
    @State private var modeFilter = "All"
    @State private var searchText = ""

    private var gridList: Binding<String> {
        Binding(get: { settings.gridIsList ? "list" : "grid" },
                set: { settings.gridIsList = ($0 == "list") })
    }

    private var filteredScans: [MacComputedScan] {
        compute.libraryScans.filter { scan in
            let modeMatches = modeFilter == "All" || scan.manifest.captureMode.rawValue == modeFilter
            let searchMatches = searchText.isEmpty || scan.name.localizedCaseInsensitiveContains(searchText)
            return modeMatches && searchMatches
        }
    }

    private var selectedScan: MacComputedScan? {
        if let selected = compute.selectedScan, filteredScans.contains(where: { $0.id == selected.id }) {
            return selected
        }
        return filteredScans.first
    }

    var body: some View {
        HStack(spacing: 0) {
            MacLibrarySidebar(
                section: $section,
                settings: settings,
                summary: compute.librarySummary,
                modeFilter: $modeFilter
            )
            .frame(width: 264)
            StRule(vertical: true)
            VStack(spacing: 0) {
                toolbar
                content
            }
        }
        .onAppear { compute.reloadLibrary() }
    }

    private var toolbar: some View {
        MacTopBar(leadingInset: 20) {
            Color.clear.frame(width: 56, height: 1)
            Text(modeFilter == "All" ? "All Scans" : "\(modeFilter) Scans")
                .font(.sf(15, .bold)).foregroundStyle(theme.ink)
            StTextChip(text: "\(filteredScans.count) \(filteredScans.count == 1 ? "item" : "items")")
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                StIcon(name: "search", size: 14, color: theme.text3)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.sf(13))
                    .foregroundStyle(theme.ink)
            }
            .frame(width: 260, height: 32)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.line, lineWidth: 0.5))
            Picker("Library layout", selection: gridList) {
                Label("Grid", systemImage: "square.grid.2x2").labelStyle(.iconOnly).tag("grid")
                Label("List", systemImage: "list.bullet").labelStyle(.iconOnly).tag("list")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 78)
            .help("Library layout")
            StButton(title: "Open", kind: .accent, size: .sm, icon: "cube") { openSelectedOrFirst() }
                .disabled(selectedScan == nil)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let selectedScan {
                    MacFeaturedResult(scan: selectedScan, section: $section, compute: compute)
                } else {
                    emptyLibrary
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Recent").font(.sf(18, .bold)).foregroundStyle(theme.ink)
                    Spacer(minLength: 0)
                    MacLibraryFilters(scans: compute.libraryScans, active: $modeFilter)
                }
                .padding(.top, 26)
                .padding(.bottom, 14)

                if filteredScans.isEmpty {
                    Text(searchText.isEmpty ? "No completed scans in this category." : "No scans match \"\(searchText)\".")
                        .font(.sf(14)).foregroundStyle(theme.text3)
                        .padding(.vertical, 22)
                } else if settings.gridIsList {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredScans.enumerated()), id: \.element.id) { index, scan in
                            MacLibraryListRow(scan: scan, selected: scan.id == selectedScan?.id) { open(scan) }
                            if index < filteredScans.count - 1 { StRule() }
                        }
                    }
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                        ForEach(filteredScans) { scan in
                            Button { open(scan) } label: { MacScanTile(scan: scan, selected: scan.id == selectedScan?.id) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var emptyLibrary: some View {
        StCard(radius: 8, pad: 28) {
            HStack(spacing: 18) {
                Image(systemName: "cube.transparent").font(.system(size: 38)).foregroundStyle(theme.accentText)
                VStack(alignment: .leading, spacing: 5) {
                    Text("No computed scans yet").font(.sf(20, .bold)).foregroundStyle(theme.ink)
                    Text("Send a capture from 3DSeen on iPhone or iPad to compute it on this Mac.")
                        .font(.sf(14)).foregroundStyle(theme.text2)
                }
                Spacer(minLength: 0)
                StButton(title: "Compute", kind: .accent, icon: "chip") { section = .compute }
            }
        }
    }

    private func open(_ scan: MacComputedScan) {
        compute.selectScan(scan.id)
        section = .viewer
    }

    private func openSelectedOrFirst() {
        if let selectedScan {
            open(selectedScan)
        } else if let first = filteredScans.first {
            open(first)
        }
    }
}

private struct MacFeaturedResult: View {
    @Environment(\.theme) private var theme
    let scan: MacComputedScan
    @Binding var section: MacSection
    @ObservedObject var compute: ComputeCoordinator

    var body: some View {
        StCard(radius: 8, pad: 22) {
            HStack(spacing: 24) {
                MacModelStage(assetURL: scan.modelURL).frame(width: 220, height: 200)
                VStack(alignment: .leading, spacing: 0) {
                    StLabel(text: "Computed model", color: theme.good)
                    Text(scan.name).font(.sf(30, .heavy)).foregroundStyle(theme.ink).padding(.top, 8)
                    Text("\(scan.manifest.captureMode.rawValue) · \(scan.manifest.detailTier) · \(scan.sizeMB) MB")
                        .font(.sf(14)).foregroundStyle(theme.text2).padding(.top, 6)
                    HStack(spacing: 30) {
                        stat("Frames", "\(scan.manifest.frameCount)")
                        stat("Detail", scan.manifest.detailTier)
                        stat("Format", scan.modelURL.pathExtension.uppercased())
                    }
                    .padding(.top, 20)
                }
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    StButton(title: "Open in 3D", kind: .accent, icon: "cube") {
                        compute.selectScan(scan.id)
                        section = .viewer
                    }
                    StButton(title: "Export…", kind: .secondary, icon: "export") {
                        compute.selectScan(scan.id)
                        section = .export
                    }
                    StButton(title: "Compute", kind: .ghost, icon: "chip") {
                        compute.selectScan(scan.id)
                        section = .compute
                    }
                }
            }
        }
    }

    private func stat(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            StLabel(text: key)
            Text(value).font(.sf(20, .bold)).monospacedDigit().foregroundStyle(theme.ink)
        }
    }
}

private struct MacScanTile: View {
    @Environment(\.theme) private var theme
    let scan: MacComputedScan
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Stage(radius: 8) {
                VStack(spacing: 8) {
                    Image(systemName: "cube").font(.system(size: 28)).foregroundStyle(theme.accentText)
                    Text(scan.modelURL.lastPathComponent).font(.mono(10)).foregroundStyle(theme.text3).lineLimit(1)
                }
                .padding(12)
            }
            .frame(height: 142)
            Text(scan.name).font(.sf(13, .semibold)).foregroundStyle(theme.ink).lineLimit(1)
            Text("\(scan.manifest.captureMode.rawValue) · \(scan.manifest.detailTier) · \(scan.sizeMB) MB")
                .font(.mono(10)).foregroundStyle(theme.text3).lineLimit(1)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? theme.accentSoft : theme.card))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(selected ? theme.accentLine : theme.line, lineWidth: selected ? 1 : 0.5))
    }
}

private struct MacLibraryListRow: View {
    @Environment(\.theme) private var theme
    let scan: MacComputedScan
    let selected: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                Image(systemName: "cube").foregroundStyle(theme.accentText).frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.fieldFill))
                VStack(alignment: .leading, spacing: 2) {
                    Text(scan.name).font(.sf(14, .semibold)).foregroundStyle(theme.ink)
                    Text("\(scan.manifest.captureMode.rawValue) · \(scan.manifest.detailTier)").font(.sf(12)).foregroundStyle(theme.text3)
                }
                Spacer(minLength: 0)
                Text("\(scan.manifest.frameCount) frames").font(.mono(11)).foregroundStyle(theme.text2).frame(width: 90, alignment: .trailing)
                Text("\(scan.sizeMB) MB").font(.mono(11)).foregroundStyle(theme.text3).frame(width: 70, alignment: .trailing)
            }
            .padding(.vertical, 10).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? theme.accentSoft : .clear))
        }
        .buttonStyle(.plain)
    }
}

private struct MacLibraryFilters: View {
    @Environment(\.theme) private var theme
    let scans: [MacComputedScan]
    @Binding var active: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(["All", "Object", "Space", "Landscape"], id: \.self) { key in
                let count = key == "All" ? scans.count : scans.filter { $0.manifest.captureMode.rawValue == key }.count
                Button { active = key } label: {
                    Text("\(key) \(count)").font(.sf(12.5, .semibold)).foregroundStyle(active == key ? theme.bg : theme.text2)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(Capsule().fill(active == key ? theme.ink : theme.fieldFill))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MacLibrarySidebarRow: Identifiable {
    let icon: String
    let title: String
    let filter: String
    let count: Int

    var id: String { filter }
}

private struct MacLibrarySidebar: View {
    @Environment(\.theme) private var theme
    @Binding var section: MacSection
    @ObservedObject var settings: SettingsStore
    let summary: MacLibrarySummary
    @Binding var modeFilter: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows) { row in
                Button { modeFilter = row.filter } label: {
                    HStack(spacing: 11) {
                        StIcon(name: row.icon, size: 17, color: row.filter == modeFilter ? theme.accent : theme.text2)
                        Text(row.title).font(.sf(14, row.filter == modeFilter ? .semibold : .regular)).foregroundStyle(row.filter == modeFilter ? theme.ink : theme.text2)
                        Spacer(minLength: 0)
                        Text("\(row.count)").font(.mono(11)).foregroundStyle(theme.text3)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(row.filter == modeFilter ? theme.fieldFillHi : .clear))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            StCard(radius: 8, pad: 13, inset: true) {
                VStack(alignment: .leading, spacing: 6) {
                    StLabel(text: "Stored models", color: theme.good)
                    Text(summary.storageText).font(.sf(20, .bold)).monospacedDigit().foregroundStyle(theme.ink)
                    Text("\(summary.scanCount) completed \(summary.scanCount == 1 ? "scan" : "scans")").font(.sf(12)).foregroundStyle(theme.text3)
                }
            }
            HStack {
                Button { section = .settings } label: { Label("Settings", systemImage: "gearshape").font(.sf(12.5)).foregroundStyle(theme.text2) }
                    .buttonStyle(.plain)
                Spacer()
                Button { settings.appearance = theme.mode == .dark ? .light : .dark } label: {
                    StIcon(name: theme.mode == .dark ? "light" : "moon", size: 14, color: theme.text2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.mode == .dark ? "Use light appearance" : "Use dark appearance")
                .help(theme.mode == .dark ? "Use light appearance" : "Use dark appearance")
            }
        }
        .padding(.top, 52).padding(.horizontal, 16).padding(.bottom, 18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.card2)
    }

    private var rows: [MacLibrarySidebarRow] {
        [
            .init(icon: "grid", title: "All Scans", filter: "All", count: summary.scanCount),
            .init(icon: "cube", title: "Objects", filter: "Object", count: summary.objectCount),
            .init(icon: "room", title: "Spaces", filter: "Space", count: summary.spaceCount),
            .init(icon: "landscape", title: "Landscapes", filter: "Landscape", count: summary.landscapeCount),
        ]
    }
}
