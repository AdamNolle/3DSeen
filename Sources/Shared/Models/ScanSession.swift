import Foundation
import SwiftData

@Model
public final class ScanSession {
    public var id: UUID
    public var creationDate: Date
    public var captureModeRaw: String
    public var usdzFileURL: URL?
    public var appliedMaterialRaw: String?
    
    // Computed properties for safe typed access
    public var captureMode: CaptureMode? {
        CaptureMode(rawValue: captureModeRaw)
    }
    
    public init(id: UUID = UUID(), creationDate: Date = Date(), captureMode: CaptureMode) {
        self.id = id
        self.creationDate = creationDate
        self.captureModeRaw = captureMode.rawValue
    }
}
