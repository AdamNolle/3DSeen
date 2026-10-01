import SwiftUI

/// The desktop scan library. Its contents are durable results retained by `ComputeCoordinator`;
/// there are no sample scans, fabricated category counts, or placeholder storage totals here.
struct MacLibraryPane: View {
    @Environment(\.theme) private var theme
    @Binding var section: MacSection
    @ObservedObject var settings: SettingsStore
    @ObservedObject var compute: ComputeCoordinator
    @Binding var modeFilter: String
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
        VStack(spacing: 0) {
            toolbar
            content
        }
        .onAppear { compute.reloadLibrary() }
    }

    private var toolbar: some View {
        MacTopBar(leadingInset: 20) {
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
            .frame(minWidth: 100, maxWidth: 220, minHeight: 32)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.line, lineWidth: 0.5))
            StSegmented(options: [("grid", "Grid"), ("list", "List")], value: gridList, size: .sm)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Library layout")
            .accessibilityValue(settings.gridIsList ? "List" : "Grid")
            .help("Library layout")
            StButton(title: "Open", kind: .accent, size: .sm, icon: "cube") { openSelectedOrFirst() }
                .disabled(selectedScan == nil)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if compute.libraryScans.isEmpty {
                    emptyLibrary
                } else {
                if let selectedScan {
                    MacFeaturedResult(scan: selectedScan, section: $section, compute: compute)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Recent").font(.sf(18, .bold)).foregroundStyle(theme.ink)
                    Spacer(minLength: 0)
                    Text("\(filteredScans.count) \(filteredScans.count == 1 ? "model" : "models")")
                        .font(.mono(11)).foregroundStyle(theme.text3)
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 16)], spacing: 16) {
                        ForEach(filteredScans) { scan in
                            Button { open(scan) } label: { MacScanTile(scan: scan, selected: scan.id == selectedScan?.id) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                }
            }
            .padding(24)
        }
    }

    private var emptyLibrary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(theme.accentText)
                .accessibilityHidden(true)
                .padding(.bottom, 30)
            StLabel(text: "Your local 3D workspace", color: theme.accentText)
            Text("Bring your world\ninto the studio.")
                .font(.sf(38, .bold)).tracking(-0.8).foregroundStyle(theme.ink)
                .padding(.top, 12)
            Text("Capture an object or space with 3DSeen on iPhone or iPad. Connect your device to reconstruct, inspect, and export it here.")
                .font(.sf(15)).foregroundStyle(theme.text2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 430, alignment: .leading)
                .padding(.top, 16)
            StButton(title: "Connect a device", kind: .accent, icon: "phone") { section = .compute }
                .padding(.top, 28)
            Label("Your scans stay on your devices", systemImage: "lock.shield")
                .font(.sf(12)).foregroundStyle(theme.text3)
                .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.vertical, 64)
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
                MacModelStage(assetURL: scan.modelURL).frame(width: 200, height: 220)
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
                    HStack(spacing: 8) {
                    StButton(title: "Open in 3D", kind: .accent, icon: "cube") {
                        compute.selectScan(scan.id)
                        section = .viewer
                    }
                    StButton(title: "Export…", kind: .secondary, icon: "export") {
                        compute.selectScan(scan.id)
                        section = .export
                    }
                    }
                    .padding(.top, 22)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
