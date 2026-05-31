import Foundation

/// Maps a persisted ScanSession into the display model used by ScanThumb / Library.
extension ScanItem {
    init(_ session: ScanSession) {
        self.init(
            id: session.id.uuidString,
            name: session.name,
            mode: session.captureMode?.rawValue ?? "Object",
            date: session.relativeDate,
            mb: session.sizeMB,
            tier: session.tierRaw,
            tone: session.toneRaw,
            tris: session.triangles
        )
    }
}
