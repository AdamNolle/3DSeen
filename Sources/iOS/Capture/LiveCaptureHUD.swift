import SwiftUI

/// Shared overlay for live capture engines. The HUD renders only status values the active engine
/// supplies, so missing telemetry is represented by absence rather than a convincing fiction.
struct LiveCaptureHUD: View {
    let status: LiveCaptureStatus
    var onPrimaryAction: (() -> Void)?
    var onFinish: (() -> Void)?

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
        HStack(spacing: 10) {
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

            Spacer(minLength: 8)

            if !status.primaryFacts.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(status.primaryFacts.enumerated()), id: \.offset) { index, fact in
                        Text(fact.uppercased())
                            .font(.mono(10.5, .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 12)
                            .overlay(alignment: .leading) {
                                if index > 0 { Rectangle().fill(.white.opacity(0.18)).frame(width: 0.5, height: 16) }
                            }
                    }
                }
                .padding(.vertical, 13)
                .liquidGlass(radius: 15, tone: .dark)
            }
        }
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
