import SwiftUI

/// macOS "Studio" — a desktop window that mirrors the design's Mac variants:
/// Library (sidebar + grid) → Viewer (stage + inspector) → Compute (pipeline dashboard)
/// → Export (workspace) → Settings (preferences). Reuses the shared Studio design system.
struct ContentView: View {
    @ObservedObject var nav: MacNav
    @StateObject private var compute = ComputeCoordinator()
    @StateObject private var settings = SettingsStore()
    @Environment(\.colorScheme) private var systemScheme

    private var dark: Bool {
        switch settings.appearance {
        case .light: return false
        case .dark: return true
        case .system: return systemScheme == .dark
        }
    }
    private var theme: Theme { dark ? .dark : .light }

    var body: some View {
        Group {
            switch nav.section {
            case .library: MacLibraryPane(section: $nav.section, settings: settings, compute: compute)
            case .viewer: MacViewerPane(section: $nav.section, compute: compute, settings: settings)
            case .compute: MacComputePane(section: $nav.section, compute: compute, network: compute.network)
            case .export: MacExportPane(section: $nav.section, compute: compute)
            case .settings: MacSettingsPane(section: $nav.section, settings: settings, compute: compute)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
        .environment(\.theme, theme)
        .preferredColorScheme(settings.colorScheme)
        .frame(minWidth: 1120, minHeight: 720)
        .alert("Confirm secure pairing", isPresented: pairingPresented) {
            Button("Reject", role: .destructive) { respondToFirstPairing(accept: false) }
            Button("Codes Match") { respondToFirstPairing(accept: true) }
        } message: {
            let request = compute.pendingPairingRequests.first
            Text("Check that \(request?.peer.displayName ?? "the device") shows the same code: \(request?.code ?? "------"). Never approve a different code.")
        }
    }

    private var pairingPresented: Binding<Bool> {
        Binding(
            get: { !compute.pendingPairingRequests.isEmpty },
            set: { if !$0, !compute.pendingPairingRequests.isEmpty { respondToFirstPairing(accept: false) } }
        )
    }

    private func respondToFirstPairing(accept: Bool) {
        guard let request = compute.pendingPairingRequests.first else { return }
        if accept {
            compute.confirmPairing(request)
        } else {
            compute.rejectPairing(request)
        }
    }
}

/// Window-level navigation, owned by the App so menu commands (⌘,) can drive it too.
@MainActor final class MacNav: ObservableObject {
    @Published var section: MacSection = .library
}

enum MacSection: String, CaseIterable {
    case library, viewer, compute, export, settings
}

// MARK: - Shared Mac chrome

/// The 52pt top toolbar shared by every Mac pane (card2 background + hairline base rule).
/// `leadingInset` clears the traffic-light controls: 84 for full-width workspaces (Viewer/
/// Compute/Export), smaller where a sidebar already occupies the top-left corner.
struct MacTopBar<Content: View>: View {
    @Environment(\.theme) private var theme
    var leadingInset: CGFloat = 84
    var trailingInset: CGFloat = 18
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 14) { content() }
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(theme.card2)
            .overlay(alignment: .bottom) { StRule() }
    }
}

/// Small "‹ Library" / "‹ Model" pill used in the Viewer/Compute/Export/Settings toolbars.
struct MacBackButton: View {
    @Environment(\.theme) private var theme
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                StIcon(name: "back", size: 15, color: theme.text2)
                Text(label).font(.sf(13, .semibold)).foregroundStyle(theme.text2)
            }
            .frame(height: 30)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.fieldFill))
        }
        .buttonStyle(.plain)
    }
}

/// Short vertical hairline used as a toolbar separator.
struct MacToolbarDivider: View {
    var body: some View { StRule(vertical: true).frame(height: 22) }
}

#Preview { ContentView(nav: MacNav()) }
