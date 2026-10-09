import RealityKit
import UIKit

enum CapturePreviewMaterials {
    static func blueprintSurface() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        let blueprintTint = UIColor(red: 0.09, green: 0.31, blue: 0.92, alpha: 1)
        material.baseColor = .init(tint: blueprintTint, texture: nil)
        material.emissiveColor = .init(color: blueprintTint)
        material.emissiveIntensity = 0.22
        material.roughness = 0.7
        material.faceCulling = .none
        material.blending = .transparent(opacity: 0.34)
        return material
    }
}
