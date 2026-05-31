import Foundation
import RealityKit
import SwiftUI
#if canImport(UIKit)
import UIKit
public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
public typealias PlatformColor = NSColor
#endif

/// A library of pre-built Physically Based Materials to drape over raw generated geometry.
public struct MaterialOverrideLibrary {

    public enum MaterialPreset: String, CaseIterable {
        case brushedMetal = "Brushed Metal"
        case mattePlastic = "Matte Plastic"
        case roughStone = "Rough Stone"
        case glossyCeramic = "Glossy Ceramic"
        case original = "Original Texture"
    }

    /// Generates a RealityKit PhysicallyBasedMaterial based on the preset.
    public static func material(for preset: MaterialPreset, baseColor: PlatformColor = .white) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: baseColor)

        switch preset {
        case .brushedMetal:
            material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.9)
            material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.3)
            material.clearcoat = PhysicallyBasedMaterial.Clearcoat(floatLiteral: 0.1)

        case .mattePlastic:
            material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.0)
            material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.8)

        case .roughStone:
            material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.0)
            material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 1.0)
            // A real implementation would apply a generated noise normal map here

        case .glossyCeramic:
            material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.0)
            material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.05)
            material.clearcoat = PhysicallyBasedMaterial.Clearcoat(floatLiteral: 1.0)

        case .original:
            // This would leave the original UV mapped textures intact
            break
        }

        return material
    }
}
