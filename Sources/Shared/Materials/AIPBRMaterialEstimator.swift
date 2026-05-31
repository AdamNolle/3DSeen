import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import OSLog

/// Infers PBR maps (roughness · metallic · normal) from a flat RGB photogrammetry texture,
/// fully on-device with Core Image. Heuristic estimator — no cloud, no bundled model — so it
/// runs offline and privately. Swap in a CoreML material model later behind the same interface.
public final class AIPBRMaterialEstimator {
    private let logger = Logger(subsystem: "com.adamnolle.3DSeen.Shared", category: "PBREstimator")
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    public init() {}

    /// Generates Roughness, Metallic, and Normal maps from an RGB input.
    public func estimateMaterials(from baseColorMap: CGImage) async throws -> PBRMaps {
        logger.info("Estimating PBR maps from base color texture (Core Image)…")
        let base = CIImage(cgImage: baseColorMap)
        let extent = base.extent

        // ── Roughness: desaturated luminance, contrast-shaped. Bright, even texture → smoother. ──
        let mono = base.applyingFilter("CIPhotoEffectMono")
        let roughnessCI = mono
            .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.15, kCIInputBrightnessKey: 0.05])
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": 0.8])

        // ── Metallic: low-saturation + high-luminance regions read as metal; most surfaces dielectric. ──
        let desaturated = base.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
        let metallicCI = desaturated
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": 2.4])   // darken → mostly non-metal
            .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.1])

        // ── Normal: Sobel-style emboss of luminance, biased toward a tangent-space blue normal. ──
        let weights = CIVector(values: [-2, -1, 0, -1, 1, 1, 0, 1, 2], count: 9)
        let emboss = mono.applyingFilter("CIConvolution3X3", parameters: [
            "inputWeights": weights, "inputBias": 0.5
        ]).cropped(to: extent)
        // Map embossed detail into R/G, force B high → normal-map appearance.
        let normalCI = emboss.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.6, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0.6, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0.2, y: 0.2, z: 1.0, w: 0)
        ])

        guard let roughness = render(roughnessCI, extent),
              let metallic = render(metallicCI, extent),
              let normal = render(normalCI, extent) else {
            throw PBRError.renderFailed
        }
        logger.info("PBR estimation complete.")
        return PBRMaps(roughness: roughness, metallic: metallic, normal: normal)
    }

    private func render(_ image: CIImage, _ extent: CGRect) -> CGImage? {
        context.createCGImage(image, from: extent)
    }

    public enum PBRError: Error { case renderFailed }
}

public struct PBRMaps {
    public let roughness: CGImage
    public let metallic: CGImage
    public let normal: CGImage
}
