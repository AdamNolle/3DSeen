// SettingsStore.swift — persisted, cross-platform user settings (no UIKit).
// Backed by UserDefaults so it works on iOS and macOS. The color-scheme mapping is a
// pure static seam (`colorScheme(for:)`) so it is unit-testable without UserDefaults.

import SwiftUI
import Combine

/// Observable, persisted settings. Inject a custom `UserDefaults` suite for testing.
final class SettingsStore: ObservableObject {

    // MARK: Choices

    enum Appearance: String, CaseIterable { case system, light, dark }
    enum DefaultMode: String, CaseIterable { case autoPilot = "auto", object, space, landscape }
    enum QualityTier: String, CaseIterable { case preview, reduced, medium, full, raw }
    enum Units: String, CaseIterable { case centimeters, inches }
    enum RawArchiveRetention: String, CaseIterable {
        case keepAll
        case latest10
        case latest5
        case latest1

        var limit: Int? {
            switch self {
            case .keepAll: nil
            case .latest10: 10
            case .latest5: 5
            case .latest1: 1
            }
        }
    }

    // MARK: Storage

    private enum Key {
        static let appearance = "settings.appearance"
        static let defaultMode = "settings.defaultMode"
        static let qualityTier = "settings.qualityTier"
        static let units = "settings.units"
        static let gridIsList = "settings.gridIsList"
        static let thermalProtectionEnabled = "settings.thermalProtectionEnabled"
        static let autoSelectTrustedMac = "settings.autoSelectTrustedMac"
        static let rawArchiveRetention = "settings.rawArchiveRetention"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Persisted values

    var appearance: Appearance {
        get { read(Key.appearance, default: .system) }
        set { write(newValue, Key.appearance) }
    }
    var defaultMode: DefaultMode {
        get { read(Key.defaultMode, default: .autoPilot) }
        set { write(newValue, Key.defaultMode) }
    }
    var qualityTier: QualityTier {
        get { read(Key.qualityTier, default: .full) }
        set { write(newValue, Key.qualityTier) }
    }
    var units: Units {
        get { read(Key.units, default: .centimeters) }
        set { write(newValue, Key.units) }
    }
    var gridIsList: Bool {
        get { defaults.bool(forKey: Key.gridIsList) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.gridIsList) }
    }
    var thermalProtectionEnabled: Bool {
        get { (defaults.object(forKey: Key.thermalProtectionEnabled) as? Bool) ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.thermalProtectionEnabled) }
    }
    var autoSelectTrustedMac: Bool {
        get { (defaults.object(forKey: Key.autoSelectTrustedMac) as? Bool) ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.autoSelectTrustedMac) }
    }
    var rawArchiveRetention: RawArchiveRetention {
        get { read(Key.rawArchiveRetention, default: .keepAll) }
        set { write(newValue, Key.rawArchiveRetention) }
    }

    // MARK: Derived

    /// SwiftUI color scheme to force; `nil` follows the system.
    var colorScheme: ColorScheme? { Self.colorScheme(for: appearance) }

    /// Pure mapping seam — testable without UserDefaults.
    static func colorScheme(for appearance: Appearance) -> ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    // MARK: Raw-value plumbing

    private func read<T: RawRepresentable>(_ key: String, default fallback: T) -> T where T.RawValue == String {
        guard let raw = defaults.string(forKey: key), let value = T(rawValue: raw) else { return fallback }
        return value
    }
    private func write<T: RawRepresentable>(_ value: T, _ key: String) where T.RawValue == String {
        objectWillChange.send()
        defaults.set(value.rawValue, forKey: key)
    }
}

/// Formats a measured SceneKit distance using the app-wide unit preference.
enum MeasurementFormatter {
    static func display(meters: Double, units: SettingsStore.Units) -> String {
        switch units {
        case .centimeters:
            return String(format: "%.1f cm", meters * 100)
        case .inches:
            return String(format: "%.1f in", meters * 39.37007874)
        }
    }
}
