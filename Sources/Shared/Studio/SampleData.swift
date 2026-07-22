// Shared presentation types used by the live library and review renderer.

import SwiftUI

enum ScanLibraryAction: String, Equatable {
    case resumeCapture
    case resumeReview
    case resumeCompute
    case retryCompute
    case view

    var title: String {
        switch self {
        case .resumeCapture, .resumeReview, .resumeCompute: return "Resume"
        case .retryCompute: return "Retry"
        case .view: return "View"
        }
    }
}

struct ScanItem: Identifiable {
    let id: String
    let name: String
    let mode: String        // Object / Space / Landscape
    let date: String
    let mb: Int
    let tier: String        // Preview / Reduced / Medium / Full / Raw
    let tone: String        // bone / rust / graphite / walnut / slate / ice
    let thumbnailURL: URL?
    let tris: String
    let primaryAction: ScanLibraryAction
    let canExport: Bool
}

struct Dropout: Identifiable {
    let id: String
    let label: String
    let severity: String    // high / med
    let x: Double           // 0..100 percent
    let y: Double
    let hint: String
}

/// Maps a scan tone to the library thumbnail accent.
extension ScanItem {
    var toneColor: Color {
        switch tone {
        case "rust":     return Color(hex: "#B0744E")
        case "graphite": return Color(hex: "#5A5A60")
        case "walnut":   return Color(hex: "#7A5A3C")
        case "slate":    return Color(hex: "#5E6B78")
        case "ice":      return Color(hex: "#9FB8C4")
        default:         return Stone.mid
        }
    }
}
