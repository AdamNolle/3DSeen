import RealityKit
import UIKit

enum CapturePreviewMaterials {
    static func blueprintSurface() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(
            tint: UIColor(red: 0.09, green: 0.31, blue: 0.92, alpha: 1),
            texture: nil
        )
        material.roughness = 0.7
        material.faceCulling = .none
        material.blending = .transparent(opacity: 0.34)
        return material
    }
}
