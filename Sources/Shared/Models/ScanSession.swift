import Foundation
import SwiftData

@Model
public final class ScanSession {
    public var id: UUID
    public var creationDate: Date
    public var captureModeRaw: String
    public var usdzFileURL: URL?
    public var appliedMaterialRaw: String?

    // Display metadata (defaulted so SwiftData lightweight migration is automatic).
    public var name: String = "New Scan"
    public var sizeMB: Int = 0
    public var tierRaw: String = "Medium"
    public var toneRaw: String = "bone"
    public var triangles: String = "—"

    // Computed properties for safe typed access
    public var captureMode: CaptureMode? {
        CaptureMode(rawValue: captureModeRaw)
    }

    public init(id: UUID = UUID(),
                creationDate: Date = Date(),
                captureMode: CaptureMode,
                name: String = "New Scan",
                sizeMB: Int = 0,
                tier: String = "Medium",
                tone: String = "bone",
                triangles: String = "—") {
        self.id = id
        self.creationDate = creationDate
        self.captureModeRaw = captureMode.rawValue
        self.name = name
        self.sizeMB = sizeMB
        self.tierRaw = tier
        self.toneRaw = tone
        self.triangles = triangles
    }

    /// Human relative date ("Today", "5d ago", "Aug 04").
    public var relativeDate: String {
        let cal = Calendar.current
        if cal.isDateInToday(creationDate) { return "Today" }
        let days = cal.dateComponents([.day], from: creationDate, to: Date()).day ?? 0
        switch days {
        case ..<1:    return "Today"
        case 1:       return "Yesterday"
        case 2...13:  return "\(days)d ago"
        case 14...27: return "\(days / 7)w ago"
        default:
            let formatter = DateFormatter(); formatter.dateFormat = "MMM dd"
            return formatter.string(from: creationDate)
        }
    }
}
