import Foundation

/// Keeps editable measurements in the database and portable scan manifest consistent.
@MainActor
public enum ScanMeasurementRecorder {
    public static func replace(
        _ measurements: [ScanMeasurement],
        on scan: ScanSession,
        assetStore: ScanAssetStore,
        save: () throws -> Void
    ) throws {
        let previous = scan.measurements
        scan.measurements = measurements
        do {
            try assetStore.writeManifest(try assetStore.manifest(for: scan))
            try save()
        } catch {
            scan.measurements = previous
            try? assetStore.writeManifest(try assetStore.manifest(for: scan))
            throw error
        }
    }
}
