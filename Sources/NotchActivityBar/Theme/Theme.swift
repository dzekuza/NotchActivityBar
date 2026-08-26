import SwiftUI
import AppKit

enum Theme {
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    static let panelBackground = adaptive(
        light: NSColor(red: 0.973, green: 0.973, blue: 0.976, alpha: 1),
        dark: NSColor(red: 0.039, green: 0.039, blue: 0.043, alpha: 1)
    )
    static let amber = adaptive(
        light: NSColor(red: 0.80, green: 0.52, blue: 0.0, alpha: 1),
        dark: NSColor(red: 1.0, green: 0.690, blue: 0.125, alpha: 1)
    )
    static let danger = adaptive(
        light: NSColor(red: 0.86, green: 0.20, blue: 0.20, alpha: 1),
        dark: NSColor(red: 1.0, green: 0.318, blue: 0.318, alpha: 1)
    )
    static let primaryText = adaptive(
        light: NSColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1),
        dark: NSColor(red: 0.961, green: 0.961, blue: 0.941, alpha: 1)
    )
    static let secondaryText = adaptive(
        light: NSColor(red: 0.42, green: 0.42, blue: 0.44, alpha: 1),
        dark: NSColor(red: 0.557, green: 0.557, blue: 0.576, alpha: 1)
    )
    static let tertiaryText = adaptive(
        light: NSColor(red: 0.58, green: 0.58, blue: 0.60, alpha: 1),
        dark: NSColor(red: 0.42, green: 0.42, blue: 0.44, alpha: 1)
    )
    static let divider = adaptive(
        light: NSColor.black.withAlphaComponent(0.08),
        dark: NSColor.white.withAlphaComponent(0.08)
    )
    static let rowHover = adaptive(
        light: NSColor.black.withAlphaComponent(0.05),
        dark: NSColor.white.withAlphaComponent(0.06)
    )

    static let cardBackground = adaptive(
        light: NSColor.black.withAlphaComponent(0.045),
        dark: NSColor.white.withAlphaComponent(0.06)
    )
    static let activeTabBackground = adaptive(
        light: NSColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1),
        dark: NSColor(red: 0.961, green: 0.961, blue: 0.941, alpha: 1)
    )
    static let activeTabText = adaptive(
        light: NSColor(red: 0.98, green: 0.98, blue: 0.96, alpha: 1),
        dark: NSColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
    )
    static let inactiveTabBackground = adaptive(
        light: NSColor.black.withAlphaComponent(0.06),
        dark: NSColor.white.withAlphaComponent(0.08)
    )
    static let inactiveTabText = adaptive(
        light: NSColor(red: 0.35, green: 0.35, blue: 0.37, alpha: 1),
        dark: NSColor(red: 0.72, green: 0.72, blue: 0.74, alpha: 1)
    )
    static let inactiveTabCountText = adaptive(
        light: NSColor(red: 0.55, green: 0.55, blue: 0.57, alpha: 1),
        dark: NSColor(red: 0.46, green: 0.46, blue: 0.48, alpha: 1)
    )

    // Hairline border drawn around cards; brightens on hover.
    static let cardBorderDefault = adaptive(
        light: NSColor.black.withAlphaComponent(0.06),
        dark: NSColor.white.withAlphaComponent(0.06)
    )
    static let cardBorderHover = adaptive(
        light: NSColor.black.withAlphaComponent(0.14),
        dark: NSColor.white.withAlphaComponent(0.16)
    )

    // Small circular buttons (delete/expand) overlaid on card artwork —
    // stays a fixed dark chip in both modes since it sits on thumbnail
    // content rather than the panel background.
    static let overlayChipBackground = Color.black.opacity(0.65)

    // Subtle button chip background used inside modals (not on artwork).
    static let overlayButtonBackground = adaptive(
        light: NSColor.black.withAlphaComponent(0.06),
        dark: NSColor.white.withAlphaComponent(0.06)
    )

    // Full-panel dimming behind a modal overlay.
    static let modalScrim = Color.black.opacity(0.55)

    static let panelCornerRadius: CGFloat = 24
    static let notchTopCornerRadius: CGFloat = 9
    static let rowCornerRadius: CGFloat = 12
    static let iconSlotCornerRadius: CGFloat = 8
    static let cardCornerRadius: CGFloat = 16

    static let idleWidth: CGFloat = 200
    static let idleHeight: CGFloat = 34
    static let toastExtraHeight: CGFloat = 32
    static let toastGap: CGFloat = 6
    static let toastPillHeight: CGFloat = 30
    static let recordingPillHeight: CGFloat = 32
    static let toastDuration: Double = 1.8
    static let fallbackMenuBarHeight: CGFloat = 24
    static let expandedWidth: CGFloat = 680
    static let expandedMaxHeight: CGFloat = 480
    /// Height budget for a tab's own content: `expandedMaxHeight` minus the
    /// search bar (60), the tab pill bar (~48), and enough room for the live
    /// recording banner (~46) that appears above the content on every tab but
    /// Meetings. A tab whose content can grow without bound must scroll within
    /// this — otherwise the panel clamps at `expandedMaxHeight` and silently
    /// clips whatever didn't fit, with no scrollbar to reveal it.
    static let expandedContentMaxHeight: CGFloat = 320
    static let cardWidth: CGFloat = 150
    static let cardImageHeight: CGFloat = 130
}
