// StudioChrome.swift — small shared chrome pieces for the capture wizard.

import SwiftUI

/// Circular icon button used throughout the wizard chrome.
struct CircleIconButton: View {
    @Environment(\.theme) private var theme
    var icon: String
    var size: CGFloat = 36
    var action: () -> Void
    var accessibilityLabel: String?
    var body: some View {
        Button(action: action) {
            StIcon(name: icon, size: 17, color: theme.text2)
                .frame(width: size, height: size)
                .background(Circle().fill(theme.fieldFill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? Self.label(for: icon))
    }

    /// Default VoiceOver label inferred from the icon name.
    static func label(for icon: String) -> String {
        switch icon {
        case "back": return "Back"
        case "close": return "Close"
        case "share": return "Share"
        case "info": return "Info"
        case "settings": return "Settings"
        default: return icon
        }
    }
}

/// Wizard top bar: back · "Step n of total" · close.
struct WizardHeader: View {
    var step: Int
    var total: Int = 4
    var onBack: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack {
            CircleIconButton(icon: "back", action: onBack)
            Spacer()
            StTextChip(text: "Step \(step) of \(total)")
            Spacer()
            CircleIconButton(icon: "close", action: onClose)
        }
    }
}

/// Bottom-pinned primary CTA used by wizard screens. Centered + width-capped on iPad.
struct BottomCTA<Label: View>: View {
    @ViewBuilder var label: Label
    var body: some View {
        VStack {
            Spacer()
            label
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
        }
    }
}

/// Centers scrolling content and caps its width on regular (iPad) size class so screens built
/// for iPhone don't stretch edge-to-edge on a tablet. No-op on compact (iPhone) width.
private struct ReadableContentWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var hSize
    var max: CGFloat
    func body(content: Content) -> some View {
        if hSize == .regular {
            content.frame(maxWidth: max).frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    /// Cap + center content width on iPad; pass-through on iPhone.
    func readableContentWidth(_ max: CGFloat = 720) -> some View {
        modifier(ReadableContentWidth(max: max))
    }

    /// Grid column count adapted to size class.
    func adaptiveColumnCount(_ compact: Int, _ regular: Int) -> Int { compact }
}

/// Reads the current horizontal size class as a column count (compact vs regular).
struct AdaptiveColumns {
    static func count(_ hSize: UserInterfaceSizeClass?, compact: Int, regular: Int) -> Int {
        hSize == .regular ? regular : compact
    }
}
