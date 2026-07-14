import SwiftUI

/// Shared preferences that have a direct, observable effect in the desktop or iOS studio.
struct MacSettingsPane: View {
    @Environment(\.theme) private var theme
    @Binding var section: MacSection
    @ObservedObject var settings: SettingsStore
    @ObservedObject var compute: ComputeCoordinator
    @State private var active: PreferenceSection = .display
    @StateObject private var runtimeInstaller = NerfstudioRuntimeInstaller()
    @State private var setupMessage = ""
    @State private var installTask: Task<Void, Never>?
    private let blenderConverter = BlenderModelConverter()

    private enum PreferenceSection: CaseIterable, Identifiable {
        case display
        case handoff
        case tools

        var id: Self { self }
        var title: String {
            switch self {
            case .display: return "Appearance & Units"
            case .handoff: return "Trusted Devices"
            case .tools: return "External Tools"
            }
        }
        var icon: String {
            switch self {
            case .display: return "light"
            case .handoff: return "phone"
            case .tools: return "settings"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 250)
            StRule(vertical: true)
            VStack(spacing: 0) {
                MacTopBar(leadingInset: 22) {
                    MacBackButton(label: "Library") { section = .library }
                    Text(active.title)
                        .font(.sf(15, .bold))
                        .foregroundStyle(theme.ink)
                    Spacer()
                }
                detail
            }
        }
        .onDisappear {
            installTask?.cancel()
            installTask = nil
            runtimeInstaller.cancel()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.sf(20, .bold))
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 10)
                .padding(.bottom, 12)

            ForEach(PreferenceSection.allCases) { preference in
                Button { active = preference } label: {
                    HStack(spacing: 11) {
                        StIcon(name: preference.icon, size: 16,
                               color: active == preference ? theme.onAccent : theme.text2)
                        Text(preference.title)
                            .font(.sf(13.5, active == preference ? .semibold : .regular))
                            .foregroundStyle(active == preference ? theme.onAccent : theme.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(active == preference ? theme.accent : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active == preference ? [.isButton, .isSelected] : .isButton)
            }

            Spacer(minLength: 0)
            Text("Preferences and local compute tools are managed on this Mac.")
                .font(.sf(12.5))
                .foregroundStyle(theme.text3)
                .padding(10)
        }
        .padding(.top, 68)
        .padding(.horizontal, 14)
        .padding(.bottom, 18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.card2)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StLabel(text: "3DSeen Studio", color: theme.accentText)
                Text(active.title)
                    .font(.sf(30, .bold))
                    .foregroundStyle(theme.ink)
                    .padding(.top, 6)
                Text(activeDescription)
                    .font(.sf(14))
                    .foregroundStyle(theme.text2)
                    .padding(.top, 8)
                preferenceCard
                    .padding(.top, 20)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(28)
        }
    }

    @ViewBuilder private var preferenceCard: some View {
        SettingsCard {
            switch active {
            case .display:
                MacSettingRow(icon: "light", label: "Appearance") {
                    StSegmented(options: [("system", "System"), ("light", "Light"), ("dark", "Dark")],
                                value: appearanceBinding, size: .sm)
                }
                StRule()
                MacSettingRow(icon: "ruler", label: "Measurement units") {
                    StSegmented(options: [("centimeters", "cm"), ("inches", "in")],
                                value: unitsBinding, size: .sm)
                }
            case .handoff:
                trustedDevices
            case .tools:
                runtimeTools
            }
        }
    }

    private var activeDescription: String {
        switch active {
        case .display: "Changes take effect immediately in the desktop studio."
        case .handoff: "Revoke devices that should no longer reconnect without code confirmation."
        case .tools: "Optional local tools used for conversion and trained splats."
        }
    }

    @ViewBuilder private var trustedDevices: some View {
        if compute.trustedPeerIDs.isEmpty {
            Text("No trusted devices. Confirming a matching six-digit code adds one here.")
                .font(.sf(13.5))
                .foregroundStyle(theme.text2)
                .padding(.vertical, 12)
        } else {
            ForEach(Array(compute.trustedPeerIDs), id: \.self) { peerID in
                MacSettingRow(icon: "phone", label: peerID.rawValue.uuidString) {
                    Button("Forget", role: .destructive) { compute.forgetPeer(peerID) }
                        .accessibilityLabel("Forget trusted device \(peerID.rawValue.uuidString)")
                }
                if peerID != compute.trustedPeerIDs.max(by: {
                    $0.rawValue.uuidString < $1.rawValue.uuidString
                }) {
                    StRule()
                }
            }
        }
    }

    private var runtimeTools: some View {
        VStack(spacing: 0) {
            MacRuntimeToolRow(
                icon: "export",
                title: "Blender conversion",
                detail: blenderConverter.isAvailable
                    ? "GLB and FBX export is available from the Export workspace."
                    : "Install Blender to enable GLB and FBX export.",
                available: blenderConverter.isAvailable
            )
            StRule()
            MacRuntimeToolRow(
                icon: "sparkle",
                title: "Trained splat runtime",
                detail: compute.trainedSplatAvailable
                    ? "COLMAP and Nerfstudio are ready for local trained-splat jobs."
                    : "Installs COLMAP and a pinned local Nerfstudio environment.",
                available: compute.trainedSplatAvailable
            )

            if !compute.trainedSplatAvailable {
                if runtimeInstaller.isInstalling {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(runtimeInstaller.stage.label).font(.sf(12.5)).foregroundStyle(theme.text2)
                    }
                    .padding(.top, 16)
                } else {
                    StButton(title: "Install trained-splat runtime", kind: .accent, size: .sm, icon: "download", full: true) {
                        installRuntime()
                    }
                    .padding(.top, 16)
                    .disabled(!runtimeInstaller.canInstall)
                }
            }

            if !setupMessage.isEmpty {
                Text(setupMessage).font(.sf(12.5)).foregroundStyle(theme.text2).padding(.top, 12)
            }
        }
    }

    private func installRuntime() {
        guard installTask == nil else { return }
        setupMessage = ""
        installTask = Task {
            defer { installTask = nil }
            do {
                try await runtimeInstaller.install()
                setupMessage = compute.refreshSplatRuntime()
                    ? "Trained-splat runtime is ready."
                    : "Setup completed, but the runtime could not be verified."
            } catch is CancellationError {
                return
            } catch {
                setupMessage = error.localizedDescription
            }
        }
    }

    private var appearanceBinding: Binding<String> {
        Binding(get: { settings.appearance.rawValue },
                set: { settings.appearance = SettingsStore.Appearance(rawValue: $0) ?? .system })
    }

    private var unitsBinding: Binding<String> {
        Binding(get: { settings.units.rawValue },
                set: { settings.units = SettingsStore.Units(rawValue: $0) ?? .centimeters })
    }

}

private struct MacRuntimeToolRow: View {
    @Environment(\.theme) private var theme
    let icon: String
    let title: String
    let detail: String
    let available: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.fieldFill)
                .frame(width: 30, height: 30)
                .overlay(StIcon(name: icon, size: 16, color: theme.text2))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.line, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.sf(14, .medium)).foregroundStyle(theme.ink)
                Text(detail).font(.sf(12)).foregroundStyle(theme.text3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            StTextChip(text: available ? "READY" : "SETUP", tone: available ? .good : .warn)
        }
        .padding(.vertical, 12)
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        StCard(radius: 18, pad: 0) {
            VStack(spacing: 0) { content }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
        }
    }
}

private struct MacSettingRow<Trailing: View>: View {
    @Environment(\.theme) private var theme
    let icon: String
    let label: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.fieldFill)
                .frame(width: 30, height: 30)
                .overlay(StIcon(name: icon, size: 16, color: theme.text2))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.line, lineWidth: 0.5))
            Text(label)
                .font(.sf(14, .medium))
                .foregroundStyle(theme.ink)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.vertical, 11)
    }
}
