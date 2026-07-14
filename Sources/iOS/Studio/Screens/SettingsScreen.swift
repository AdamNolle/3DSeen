// SettingsScreen.swift — persisted preferences with no placeholder account or device state.

import SwiftData
import SwiftUI

private enum SettingsSection: Int, CaseIterable, Identifiable {
    case capture
    case display
    case handoff
    case storage

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .capture: return "Capture Defaults"
        case .display: return "Appearance & Units"
        case .handoff: return "Trusted Devices"
        case .storage: return "Storage Maintenance"
        }
    }

    var icon: String {
        switch self {
        case .capture: return "camera"
        case .display: return "light"
        case .handoff: return "mac"
        case .storage: return "download"
        }
    }
}

private let captureModeOptions = [
    ("auto", "Auto-Pilot"),
    ("object", "Object"),
    ("space", "Space"),
    ("landscape", "Landscape"),
]

private let qualityOptions = [
    ("preview", "Preview"),
    ("reduced", "Reduced"),
    ("medium", "Medium"),
    ("full", "Full"),
    ("raw", "Raw"),
]

private let appearanceOptions = [
    ("system", "System"),
    ("light", "Light"),
    ("dark", "Dark"),
]

private let unitOptions = [
    ("centimeters", "Centimeters"),
    ("inches", "Inches"),
]

private let retentionOptions = [
    ("keepAll", "Keep all raw archives"),
    ("latest10", "Keep latest 10"),
    ("latest5", "Keep latest 5"),
    ("latest1", "Keep latest 1"),
]

struct SettingsScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var model: StudioModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var handoff: IOSHandoffCoordinator
    @Query private var savedScans: [ScanSession]
    @State private var activeSection: SettingsSection = .capture
    @State private var storageAudit = ScanStorageAudit(orphanURLs: [], totalBytes: 0)
    @State private var storageMessage = ""
    @State private var isCleaningStorage = false

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
                iPadBody
            } else {
                iPhoneBody
            }
        }
        .task { await refreshStorageAudit() }
    }

    private var iPhoneBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Text("Settings")
                    .font(.sf(32, .bold))
                    .foregroundStyle(theme.ink)
                    .padding(.top, 22)
                Text("Preferences for new scans and measurement display.")
                    .font(.sf(13.5))
                    .foregroundStyle(theme.text2)
                    .padding(.top, 6)

                ForEach(SettingsSection.allCases) { section in
                    StLabel(text: section.title)
                        .padding(.top, 22)
                        .padding(.bottom, 8)
                        .padding(.horizontal, 4)
                    sectionCard(section)
                }

                Text("Captured scans are always saved to the Library so their raw assets remain available for reconstruction and export.")
                    .font(.sf(12.5))
                    .foregroundStyle(theme.text3)
                    .padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 36)
        }
    }

    private var header: some View {
        HStack {
            CircleIconButton(icon: "back") { model.go(.library) }
            Spacer()
            StTextChip(text: "Settings")
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
    }

    private var iPadBody: some View {
        HStack(alignment: .top, spacing: 20) {
            sidebar
                .frame(width: 264)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
    }

    private var sidebar: some View {
        StCard(radius: 20, pad: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Settings")
                        .font(.sf(18, .bold))
                        .foregroundStyle(theme.ink)
                    Spacer()
                    CircleIconButton(icon: "back", size: 32) { model.go(.library) }
                }
                .padding(8)

                StRule().padding(.vertical, 4)

                ForEach(SettingsSection.allCases) { section in
                    Button { activeSection = section } label: {
                        HStack(spacing: 11) {
                            StIcon(name: section.icon, size: 16,
                                   color: activeSection == section ? theme.accent : theme.text2)
                            Text(section.title)
                                .font(.sf(13.5, activeSection == section ? .semibold : .medium))
                                .foregroundStyle(activeSection == section ? theme.ink : theme.text2)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(activeSection == section ? theme.fieldFillHi : .clear))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(activeSection == section ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StLabel(text: "3DSeen Studio", color: theme.accentText)
                Text(activeSection.title)
                    .font(.sf(32, .bold))
                    .foregroundStyle(theme.ink)
                    .padding(.top, 6)
                Text(activeSectionDescription)
                    .font(.sf(13.5))
                    .foregroundStyle(theme.text2)
                    .padding(.top, 8)
                sectionCard(activeSection)
                    .padding(.top, 20)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder private func sectionCard(_ section: SettingsSection) -> some View {
        SettingsCard {
            switch section {
            case .capture:
                MenuSettingRow(icon: "cube", label: "Default mode", options: captureModeOptions, selection: defaultModeBinding)
                StRule()
                MenuSettingRow(icon: "layers", label: "Default Mac detail tier", options: qualityOptions, selection: qualityBinding)
                StRule()
                SettingsRow(icon: "thermal", label: "Thermal protection") {
                    Toggle("Thermal protection", isOn: thermalProtectionBinding)
                        .labelsHidden()
                        .accessibilityHint("Cancels and requeues on-device compute if the device reaches a serious thermal state.")
                }
            case .display:
                MenuSettingRow(icon: "light", label: "Appearance", options: appearanceOptions, selection: appearanceBinding)
                StRule()
                MenuSettingRow(icon: "ruler", label: "Measurement units", options: unitOptions, selection: unitsBinding)
            case .handoff:
                SettingsRow(icon: "laptop", label: "Automatically select trusted Mac") {
                    Toggle("Automatically select trusted Mac", isOn: autoSelectTrustedMacBinding)
                        .labelsHidden()
                        .accessibilityHint("Selects one authenticated Mac on the Compute screen without sending until you confirm.")
                }
                StRule()
                trustedDevices
            case .storage:
                MenuSettingRow(
                    icon: "download",
                    label: "Raw archive retention",
                    options: retentionOptions,
                    selection: rawArchiveRetentionBinding
                )
                StRule()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Retention removes only app-owned raw archives from completed scans. Models, previews, exports, and active scans remain available.")
                        .font(.sf(12.5))
                        .foregroundStyle(theme.text3)
                    StButton(
                        title: "Apply Raw Retention Now",
                        kind: .secondary,
                        size: .sm,
                        icon: "trash",
                        full: true
                    ) { applyRawArchiveRetention() }
                    .disabled(isCleaningStorage || settings.rawArchiveRetention.limit == nil)
                }
                .padding(.vertical, 12)
                StRule()
                SettingsRow(icon: "download", label: "Orphaned app storage") {
                    Text("\(storageAudit.itemCount) items · \(storageAudit.formattedSize)")
                        .font(.sf(13.5))
                        .foregroundStyle(theme.text2)
                }
                StRule()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Only directories with no matching saved scan and interrupted deletion staging are eligible. Live scans are never removed.")
                        .font(.sf(12.5))
                        .foregroundStyle(theme.text3)
                    StButton(
                        title: isCleaningStorage ? "Cleaning…" : "Clean Orphaned Files",
                        kind: .secondary,
                        size: .sm,
                        icon: "trash",
                        full: true
                    ) { cleanOrphanedStorage() }
                    .disabled(isCleaningStorage || storageAudit.itemCount == 0)
                    if !storageMessage.isEmpty {
                        Text(storageMessage).font(.sf(12.5)).foregroundStyle(theme.text2)
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder private var trustedDevices: some View {
        if handoff.trustedPeerIDs.isEmpty {
            Text("No trusted Macs. Approving a matching six-digit code adds one here.")
                .font(.sf(13.5))
                .foregroundStyle(theme.text2)
                .padding(.vertical, 12)
        } else {
            ForEach(Array(handoff.trustedPeerIDs), id: \.self) { peerID in
                SettingsRow(icon: "mac", label: peerID.rawValue.uuidString) {
                    Button("Forget", role: .destructive) { handoff.forgetPeer(peerID) }
                        .accessibilityLabel("Forget trusted Mac \(peerID.rawValue.uuidString)")
                }
                if peerID != handoff.trustedPeerIDs.max(by: {
                    $0.rawValue.uuidString < $1.rawValue.uuidString
                }) {
                    StRule()
                }
            }
        }
    }

    private var activeSectionDescription: String {
        switch activeSection {
        case .capture: return "Used each time you begin a new scan from the Library."
        case .display: return "Applied immediately to the interface and model measurements."
        case .handoff: return "Revoke Macs that should no longer reconnect without code confirmation."
        case .storage: return "Review and explicitly remove app-owned files that no longer belong to a saved scan."
        }
    }

    private func refreshStorageAudit() async {
        do {
            let liveIDs = Set(savedScans.map(\.id))
            let manager = try ScanLifecycleManager()
            storageAudit = try await Task.detached(priority: .utility) {
                try manager.auditStorage(liveScanIDs: liveIDs)
            }.value
        } catch {
            storageMessage = "Storage could not be inspected: \(error.localizedDescription)"
        }
    }

    private func applyRawArchiveRetention() {
        guard !isCleaningStorage, let limit = settings.rawArchiveRetention.limit else { return }
        isCleaningStorage = true
        defer { isCleaningStorage = false }
        do {
            let manager = try ScanLifecycleManager()
            let removed = try manager.applyRawArchiveRetention(to: savedScans, keepLatest: limit) {
                try modelContext.save()
            }
            storageMessage = removed == 1
                ? "Removed 1 old raw archive."
                : "Removed \(removed) old raw archives."
        } catch {
            storageMessage = "Raw retention stopped safely: \(error.localizedDescription)"
        }
    }

    private func cleanOrphanedStorage() {
        guard !isCleaningStorage else { return }
        isCleaningStorage = true
        let audit = storageAudit
        let liveIDs = Set(savedScans.map(\.id))
        Task {
            defer { isCleaningStorage = false }
            do {
                let manager = try ScanLifecycleManager()
                try await Task.detached(priority: .utility) {
                    try manager.clean(audit, liveScanIDs: liveIDs)
                }.value
                storageMessage = "Removed \(audit.itemCount) orphaned items."
            } catch {
                storageMessage = "Cleanup stopped safely: \(error.localizedDescription)"
            }
            await refreshStorageAudit()
        }
    }

    private var defaultModeBinding: Binding<String> {
        Binding(get: { settings.defaultMode.rawValue },
                set: { settings.defaultMode = SettingsStore.DefaultMode(rawValue: $0) ?? .object })
    }

    private var qualityBinding: Binding<String> {
        Binding(get: { settings.qualityTier.rawValue },
                set: { settings.qualityTier = SettingsStore.QualityTier(rawValue: $0) ?? .full })
    }

    private var autoSelectTrustedMacBinding: Binding<Bool> {
        Binding(get: { settings.autoSelectTrustedMac }, set: { settings.autoSelectTrustedMac = $0 })
    }

    private var rawArchiveRetentionBinding: Binding<String> {
        Binding(
            get: { settings.rawArchiveRetention.rawValue },
            set: {
                settings.rawArchiveRetention = SettingsStore.RawArchiveRetention(rawValue: $0) ?? .keepAll
            }
        )
    }

    private var appearanceBinding: Binding<String> {
        Binding(get: { settings.appearance.rawValue },
                set: { settings.appearance = SettingsStore.Appearance(rawValue: $0) ?? .system })
    }

    private var unitsBinding: Binding<String> {
        Binding(get: { settings.units.rawValue },
                set: { settings.units = SettingsStore.Units(rawValue: $0) ?? .centimeters })
    }

    private var thermalProtectionBinding: Binding<Bool> {
        Binding(get: { settings.thermalProtectionEnabled }, set: { settings.thermalProtectionEnabled = $0 })
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

private struct SettingsRow<Trailing: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let icon: String
    let label: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    rowLabel
                    trailing
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 42)
                }
            } else {
                HStack(spacing: 12) {
                    rowLabel
                    Spacer(minLength: 0)
                    trailing
                }
            }
        }
        .padding(.vertical, 11)
    }

    private var rowLabel: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.fieldFill)
                .frame(width: 30, height: 30)
                .overlay(StIcon(name: icon, size: 16, color: theme.text2))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.line, lineWidth: 0.5))
            Text(label)
                .font(.sf(14, .medium))
                .foregroundStyle(theme.ink)
        }
    }
}

private struct MenuSettingRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let icon: String
    let label: String
    let options: [(String, String)]
    @Binding var selection: String
    @State private var isChoosingOption = false

    private var currentLabel: String {
        options.first { $0.0 == selection }?.1 ?? selection
    }

    var body: some View {
        SettingsRow(icon: icon, label: label) {
            Button {
                isChoosingOption = true
            } label: {
                HStack(spacing: 6) {
                    Text(currentLabel).font(.sf(13.5)).foregroundStyle(theme.text2)
                    StIcon(name: "chev", size: 14, color: theme.text4)
                }
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
                .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(currentLabel)
            .confirmationDialog(label, isPresented: $isChoosingOption, titleVisibility: .visible) {
                ForEach(options, id: \.0) { option in
                    Button {
                        selection = option.0
                    } label: {
                        Text(option.0 == selection ? "\(option.1) (Current)" : option.1)
                    }
                }
            }
        }
    }
}
