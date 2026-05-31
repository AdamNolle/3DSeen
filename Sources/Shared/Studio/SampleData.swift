// SampleData.swift — shared sample data across Studio screens (ported from studio/data.jsx)
// Used by the design prototype until screens are wired to the live capture/compute engine.

import SwiftUI

struct ScanItem: Identifiable {
    let id: String
    let name: String
    let mode: String        // Object / Space / Landscape
    let date: String
    let mb: Int
    let tier: String        // Preview / Reduced / Medium / Full / Raw
    let tone: String        // bone / rust / graphite / walnut / slate / ice
    let tris: String
}

/// UI metadata for an export format row (distinct from the engine's `ExportFormat` enum).
struct ExportFormatInfo: Identifiable {
    let id: String
    let name: String
    let ext: String
    let size: String
    let desc: String
    var best: Bool = false
}

struct Measurement: Identifiable {
    let id: String
    let label: String
    let value: String
    let unit: String
}

struct Dropout: Identifiable {
    let id: String
    let label: String
    let severity: String    // high / med
    let x: Double           // 0..100 percent
    let y: Double
    let hint: String
}

enum SampleData {
    static let scans: [ScanItem] = [
        .init(id: "celestial", name: "Celestial Bust", mode: "Object", date: "Today", mb: 184, tier: "Full", tone: "bone", tris: "4.2M"),
        .init(id: "amaranth", name: "Amaranth Vase", mode: "Object", date: "5d ago", mb: 92, tier: "Medium", tone: "rust", tris: "1.2M"),
        .init(id: "studio", name: "Studio Floor 02", mode: "Space", date: "1w ago", mb: 412, tier: "Full", tone: "graphite", tris: "5.1M"),
        .init(id: "desk", name: "Walnut Desk", mode: "Object", date: "1w ago", mb: 76, tier: "Reduced", tone: "walnut", tris: "480k"),
        .init(id: "falls", name: "Granite Falls", mode: "Landscape", date: "2w ago", mb: 1140, tier: "Raw", tone: "slate", tris: "16M"),
        .init(id: "arch", name: "Archive Shelf", mode: "Space", date: "3w ago", mb: 264, tier: "Full", tone: "ice", tris: "3.4M"),
        .init(id: "ceramic", name: "Ceramic Pour", mode: "Object", date: "3w ago", mb: 58, tier: "Preview", tone: "bone", tris: "120k"),
        .init(id: "tape", name: "Cassette Maxell", mode: "Object", date: "Aug 04", mb: 124, tier: "Full", tone: "graphite", tris: "4.0M"),
    ]

    static let exportFormats: [ExportFormatInfo] = [
        .init(id: "usdz", name: "USDZ", ext: ".usdz", size: "184 MB", desc: "AR Quick Look · Apple-native", best: true),
        .init(id: "usd", name: "USD", ext: ".usdc", size: "212 MB", desc: "Pixar OpenUSD · pipelines"),
        .init(id: "glb", name: "glTF", ext: ".glb", size: "156 MB", desc: "Universal · web · Blender"),
        .init(id: "obj", name: "OBJ", ext: ".obj + mtl", size: "298 MB", desc: "Legacy DCC interchange"),
        .init(id: "fbx", name: "FBX", ext: ".fbx", size: "188 MB", desc: "Unreal · Unity · Maya"),
        .init(id: "ply", name: "PLY", ext: ".ply", size: "440 MB", desc: "Point cloud · raw archive"),
    ]

    static let measurements: [Measurement] = [
        .init(id: "M01", label: "Height · chin to crown", value: "14.20", unit: "cm"),
        .init(id: "M02", label: "Shoulder width", value: "11.84", unit: "cm"),
        .init(id: "M03", label: "Nose to ear", value: "3.10", unit: "cm"),
    ]

    static let dropouts: [Dropout] = [
        .init(id: "crown", label: "Crown of head", severity: "high", x: 50, y: 22, hint: "Lift camera 25° higher"),
        .init(id: "earl", label: "Back-left ear", severity: "med", x: 24, y: 42, hint: "Walk 15° clockwise"),
        .init(id: "under", label: "Underside", severity: "med", x: 50, y: 84, hint: "Tilt down 25°"),
    ]
}

/// Maps a scan "tone" name to a warm stone-ish accent for placeholder thumbnails.
extension ScanItem {
    var toneColor: Color {
        switch tone {
        case "rust":     return Color(hex: "#B0744E")
        case "graphite": return Color(hex: "#5A5A60")
        case "walnut":   return Color(hex: "#7A5A3C")
        case "slate":    return Color(hex: "#5E6B78")
        case "ice":      return Color(hex: "#9FB8C4")
        default:         return Stone.mid // bone
        }
    }
}
