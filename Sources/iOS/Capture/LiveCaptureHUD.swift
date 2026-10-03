import SwiftUI

/// Shared overlay for live capture engines. The HUD renders only status values the active engine
/// supplies, so missing telemetry is represented by absence rather than a convincing fiction.
struct LiveCaptureHUD: View {
    let status: LiveCaptureStatus
    var onPrimaryAction: (() -> Void)?
    var onFinish: (() -> Void)?
    var onTextureCapture: (() -> Void)?
    var textureSnapshotCount = 0

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header
                    .padding(.top, proxy.safeAreaInsets.top + 10)
                Spacer(minLength: 20)
                bottomPanel
                    .padding(.bottom, proxy.safeAreaInsets.bottom + 20)
            }
            .padding(.horizontal, proxy.size.width >= 700 ? 24 : 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(true)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    titlePill
                    Spacer(minLength: 8)
                    factsPill
                }
                VStack(alignment: .leading, spacing: 8) {
                    titlePill
                    factsPill
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let summary = status.surfaceClassificationSummary {
                Label("FACE TYPES · \(summary.uppercased())", systemImage: "square.3.layers.3d")
                    .font(.mono(9.5, .semibold))
                    .tracking(0.45)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .liquidGlass(radius: 13, tone: .dark)
            }
        }
    }

    private var titlePill: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title).font(.sf(15, .bold)).foregroundStyle(.white)
                Text(status.phaseLabel.uppercased())
                    .font(.mono(9.5, .semibold)).tracking(1)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .liquidGlass(radius: 15, tone: .dark)
    }

    @ViewBuilder
    private var factsPill: some View {
        let facts = status.primaryFacts
        if !facts.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                        metric(fact)
                            .padding(.horizontal, 12)
                            .overlay(alignment: .leading) {
                                if index > 0 {
                                    Rectangle().fill(.white.opacity(0.18)).frame(width: 0.5, height: 16)
                                }
                            }
                    }
                }
                LazyVGrid(
                    columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                    alignment: .leading,
                    spacing: 4
                ) {
                    ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                        metric(fact)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 13)
            .liquidGlass(radius: 15, tone: .dark)
        }
    }

    private func metric(_ fact: String) -> some View {
        Text(fact.uppercased())
            .font(.mono(10.5, .semibold))
            .foregroundStyle(.white.opacity(0.9))
    }

    private var bottomPanel: some View {
        VStack(spacing: 12) {
            Text(status.guidance)
                .font(.sf(14, .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: 620)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .liquidGlass(radius: 16, tone: .dark)

            if let primaryActionTitle = status.primaryActionTitle, let onPrimaryAction {
                Button(action: onPrimaryAction) {
                    Label(primaryActionTitle, systemImage: "viewfinder")
                        .font(.sf(16, .semibold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 220)
                        .padding(.horizontal, 20)
                        .frame(height: 52)
                        .background(Capsule().fill(Color.accentColor.opacity(0.92)))
                }
                .buttonStyle(StPressStyle())
                .accessibilityLabel(primaryActionTitle)
            }

            if let onTextureCapture {
                Button(action: onTextureCapture) {
                    Label("Save material swatch · \(textureSnapshotCount)", systemImage: "viewfinder")
                        .font(.sf(15, .semibold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 220, minHeight: 44)
                        .background(Capsule().fill(.white.opacity(0.16)))
                }
                .buttonStyle(StPressStyle())
                .accessibilityLabel("Save material swatch")
                .accessibilityHint("Saves a center camera crop as a reusable reference image. Live surface textures are projected automatically onto measured mesh faces.")
            }

            if let finishActionTitle = status.finishActionTitle, let onFinish {
                Button(action: onFinish) {
                    Label(finishActionTitle, systemImage: "checkmark.circle.fill")
                        .font(.sf(16, .semibold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 220)
                        .padding(.horizontal, 20)
                        .frame(height: 52)
                        .background(Capsule().fill(Color.green.opacity(0.9)))
                }
                .buttonStyle(StPressStyle())
                .accessibilityLabel(finishActionTitle)
            }
        }
    }

    private var symbolName: String {
        switch status.mode {
        case .object: return "cube"
        case .space: return "house"
        case .landscape: return "mountain.2"
        case .autoPilot: return "sparkles"
        }
    }
}
