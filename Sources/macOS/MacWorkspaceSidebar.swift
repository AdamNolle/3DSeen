import SwiftUI

/// Stable desktop navigation keeps the selected scan available across its working surfaces.
struct MacWorkspaceSidebar: View {
    @Environment(\.theme) private var theme
    @ObservedObject var nav: MacNav
    @ObservedObject var compute: ComputeCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 11) {
                Image("BrandIcon")
                    .resizable().frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("3DSeen").font(.sf(19, .bold)).foregroundStyle(theme.ink)
                    Text("STUDIO").font(.mono(9, .semibold)).tracking(2).foregroundStyle(theme.text3)
                }
            }
            .padding(.horizontal, 8)

            VStack(spacing: 4) {
                row("Library", icon: "square.grid.2x2", section: .library, shortcut: "1")
                row("Compute", icon: "cpu", section: .compute, shortcut: "2")
                row("Viewer", icon: "cube", section: .viewer, shortcut: "3")
                    .disabled(compute.selectedScan == nil)
                row("Export", icon: "square.and.arrow.up", section: .export, shortcut: "4")
                    .disabled(compute.selectedScan == nil)
            }

            VStack(alignment: .leading, spacing: 5) {
                StLabel(text: "Library").padding(.horizontal, 12).padding(.bottom, 5)
                ForEach(["All", "Object", "Space", "Landscape"], id: \.self) { mode in
                    Button {
                        nav.libraryFilter = mode
                        nav.section = .library
                    } label: {
                        HStack {
                            Text(mode == "All" ? "All scans" : mode == "Space" ? "Spaces" : "\(mode)s")
                            Spacer()
                            Text("\(count(for: mode))").font(.mono(11)).monospacedDigit()
                        }
                        .font(.sf(12.5))
                        .foregroundStyle(nav.section == .library && nav.libraryFilter == mode ? theme.ink : theme.text2)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(
                            nav.section == .library && nav.libraryFilter == mode ? theme.fieldFill : .clear
                        ))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(nav.section == .library && nav.libraryFilter == mode ? .isSelected : [])
                }
            }

            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 8) {
                StRule()
                HStack {
                    Text("On this Mac").font(.sf(11.5)).foregroundStyle(theme.text3)
                    Spacer()
                    Text(compute.librarySummary.storageText).font(.mono(11)).foregroundStyle(theme.text2)
                }
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield").font(.system(size: 11))
                    Text("Local processing").font(.sf(11.5))
                }
                .foregroundStyle(theme.text3)
            }
            .padding(.horizontal, 10)
            row("Settings", icon: "gearshape", section: .settings, shortcut: ",")
        }
        .padding(.horizontal, 12).padding(.top, 56).padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }

    private func count(for mode: String) -> Int {
        mode == "All" ? compute.libraryScans.count : compute.libraryScans.filter { $0.manifest.captureMode.rawValue == mode }.count
    }

    private func row(_ title: String, icon: String, section: MacSection, shortcut: KeyEquivalent) -> some View {
        let selected = nav.section == section
        return Button { nav.section = section } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 15, weight: .medium)).frame(width: 20)
                Text(title).font(.sf(13, selected ? .semibold : .medium))
                Spacer(minLength: 0)
                if section == .compute && compute.isProcessing {
                    ProgressView().controlSize(.mini).accessibilityLabel("Compute in progress")
                }
            }
            .foregroundStyle(selected ? theme.accentText : theme.text2)
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? theme.accentSoft : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: .command)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
