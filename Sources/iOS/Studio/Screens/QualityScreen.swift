import SwiftUI

struct DetailTier: Identifiable, Equatable {
    let id: String
    let name: String
    let tag: String
    let use: String
    var recommended = false
}

let DETAIL_TIERS: [DetailTier] = [
    .init(id: "preview", name: "Preview", tag: "Fastest Mac request", use: "Fast inspection when fidelity is not the priority"),
    .init(id: "reduced", name: "Reduced", tag: "Mobile-sized request", use: "The detail level used by on-device RealityKit output"),
    .init(id: "medium", name: "Medium", tag: "Balanced Mac request", use: "General-purpose reconstruction", recommended: true),
    .init(id: "full", name: "Full", tag: "High-detail Mac request", use: "Slower reconstruction with more retained detail"),
    .init(id: "raw", name: "Raw", tag: "Source-preserving Mac request", use: "Archive-oriented reconstruction from the original photos"),
]

struct GuidedQualityChoice: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let summary: String
    let tierID: String
    let note: String
    var recommended = false

    static let choices: [GuidedQualityChoice] = [
        .init(
            id: "quick",
            name: "Quick",
            icon: "quick",
            summary: "Faster reconstruction and smaller output.",
            tierID: "reduced",
            note: "Good for previews and easy sharing."
        ),
        .init(
            id: "balanced",
            name: "Balanced",
            icon: "balanced",
            summary: "A practical mix of detail and processing time.",
            tierID: "medium",
            note: "Best starting point for most scans.",
            recommended: true
        ),
        .init(
            id: "maximum",
            name: "Maximum",
            icon: "maximum",
            summary: "Retain more detail when time and file size matter less.",
            tierID: "full",
            note: "Usually best reconstructed on a Mac."
        ),
    ]

    static func choice(forTierID tierID: String) -> GuidedQualityChoice {
        switch tierID {
        case "preview", "reduced": return choices[0]
        case "medium": return choices[1]
        default: return choices[2]
        }
    }
}

struct QualityScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var model: StudioModel
    @State private var showsAdvanced = false

    private var selectedChoice: GuidedQualityChoice {
        GuidedQualityChoice.choice(forTierID: model.selectedDetailTier)
    }

    private var selectedTier: DetailTier {
        DETAIL_TIERS.first { $0.id == model.selectedDetailTier } ?? DETAIL_TIERS[2]
    }

    private var usesAdvancedTier: Bool {
        selectedChoice.tierID != model.selectedDetailTier
    }

    private var columns: [GridItem] {
        horizontalSizeClass == .regular
            ? Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)
            : [GridItem(.flexible())]
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WizardHeader(
                        step: 3,
                        onBack: { model.go(.briefing) },
                        onClose: { model.go(.library) }
                    )
                    titleBlock
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(GuidedQualityChoice.choices) { choice in
                            qualityCard(choice)
                        }
                    }
                    advancedDisclosure
                    captureFacts
                }
                .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: 1080)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomCTA {
                StButton(
                    title: "Start Capture",
                    kind: .accent,
                    size: .lg,
                    icon: "camera",
                    full: true
                ) { model.go(.capture) }
                .accessibilityHint("Starts the guided camera using the selected reconstruction choice")
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            StLabel(text: "Step 3 · Result")
            Text("Choose your result")
                .font(.sf(horizontalSizeClass == .regular ? 38 : 28, .bold))
                .foregroundStyle(theme.ink)
            Text("Capture keeps the original photos. This choice sets the reconstruction request and can be changed later.")
                .font(.sf(14))
                .foregroundStyle(theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func qualityCard(_ choice: GuidedQualityChoice) -> some View {
        let isSelected = selectedChoice.id == choice.id
        return Button {
            model.selectedDetailTier = choice.tierID
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? theme.accent : theme.fieldFill)
                        .frame(width: 50, height: 50)
                        .overlay(StIcon(
                            name: choice.icon,
                            size: 23,
                            color: isSelected ? theme.onAccent : theme.accentText
                        ))
                    Spacer()
                    if choice.recommended {
                        StTextChip(text: "Recommended", tone: .accent)
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.accent)
                            .accessibilityHidden(true)
                    }
                }
                Text(choice.name)
                    .font(.sf(21, .bold))
                    .foregroundStyle(theme.ink)
                Text(choice.summary)
                    .font(.sf(14))
                    .foregroundStyle(theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(choice.note)
                    .font(.sf(12.5, .medium))
                    .foregroundStyle(theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: horizontalSizeClass == .regular ? 210 : 0, alignment: .topLeading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? theme.accentSoft : theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? theme.accentLine : theme.line, lineWidth: isSelected ? 1.5 : 0.5)
            )
            .stShadow(theme.cardShadow)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(choice.name). \(choice.summary) \(choice.note)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var advancedDisclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showsAdvanced.toggle() }
            } label: {
                HStack {
                    Label("Advanced controls", systemImage: "slider.horizontal.3")
                        .font(.sf(15, .semibold))
                    Spacer()
                    Text(usesAdvancedTier ? selectedTier.name : "Optional")
                        .font(.sf(12.5))
                        .foregroundStyle(theme.text3)
                    Image(systemName: showsAdvanced ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.text3)
                }
                .foregroundStyle(theme.ink)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Advanced controls")
            .accessibilityValue(showsAdvanced ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows the five exact reconstruction tiers and compute constraints")

            if showsAdvanced {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Exact reconstruction request")
                        .font(.sf(13, .semibold))
                        .foregroundStyle(theme.text2)
                    ForEach(DETAIL_TIERS) { tier in
                        advancedTierRow(tier)
                    }
                    Text("On-device RealityKit reconstruction currently uses Reduced regardless of the Mac request. Preview, Medium, Full, and Raw require the Mac handoff path.")
                        .font(.sf(12.5))
                        .foregroundStyle(theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(.top, 14)
                .transition(.opacity)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(theme.line, lineWidth: 0.5))
    }

    private func advancedTierRow(_ tier: DetailTier) -> some View {
        let isSelected = model.selectedDetailTier == tier.id
        return Button {
            model.selectedDetailTier = tier.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? theme.accent : theme.text3)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.name).font(.sf(14, .semibold)).foregroundStyle(theme.ink)
                    Text("\(tier.tag) · \(tier.use)")
                        .font(.sf(12.5))
                        .foregroundStyle(theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tier.name), \(tier.tag), \(tier.use)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var captureFacts: some View {
        Label(
            "More photos and even lighting usually matter more than choosing a higher tier.",
            systemImage: "lightbulb"
        )
        .font(.sf(13))
        .foregroundStyle(theme.text2)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
    }
}
