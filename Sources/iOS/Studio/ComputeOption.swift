import SwiftUI

struct ComputeOption: Identifiable {
    let id: String
    let name: String
    let icon: String
    let tag: String
    var best: Bool = false
    let stats: [(String, String, Color?)]
}

extension ComputeOption {
    /// Performance and battery predictions depend on hardware and input images, so these targets
    /// expose only the output tier the app can actually request.
    static func pair(_ theme: Theme, requestedTier: String) -> (mac: ComputeOption, local: ComputeOption) {
        let macTier = ComputeDetailCapability.effectiveTier(for: .macHandoff, requestedTier: requestedTier)
        let localTier = ComputeDetailCapability.effectiveTier(for: .onDevice, requestedTier: requestedTier)
        return (
            ComputeOption(
                id: "mac",
                name: "Use a Mac",
                icon: "laptop",
                tag: "Requested \(macTier) output",
                stats: [("Output", macTier, theme.accentText)]
            ),
            ComputeOption(
                id: "local",
                name: "Build on This Device",
                icon: "chip",
                tag: "RealityKit · \(localTier) output",
                stats: [("Output", localTier, theme.warn)]
            )
        )
    }
}
