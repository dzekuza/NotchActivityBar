import SwiftUI

enum Theme {
    static let panelBackground = Color(red: 0.039, green: 0.039, blue: 0.043)
    static let amber = Color(red: 1.0, green: 0.690, blue: 0.125)
    static let danger = Color(red: 1.0, green: 0.318, blue: 0.318)
    static let primaryText = Color(red: 0.961, green: 0.961, blue: 0.941)
    static let secondaryText = Color(red: 0.557, green: 0.557, blue: 0.576)
    static let tertiaryText = Color(red: 0.42, green: 0.42, blue: 0.44)
    static let divider = Color.white.opacity(0.08)
    static let rowHover = Color.white.opacity(0.06)

    static let cardBackground = Color.white.opacity(0.06)
    static let activeTabBackground = Color(red: 0.961, green: 0.961, blue: 0.941)
    static let activeTabText = Color(red: 0.05, green: 0.05, blue: 0.06)
    static let inactiveTabBackground = Color.white.opacity(0.08)
    static let inactiveTabText = Color(red: 0.72, green: 0.72, blue: 0.74)
    static let inactiveTabCountText = Color(red: 0.46, green: 0.46, blue: 0.48)

    static let panelCornerRadius: CGFloat = 24
    static let rowCornerRadius: CGFloat = 12
    static let iconSlotCornerRadius: CGFloat = 8
    static let cardCornerRadius: CGFloat = 16

    static let idleWidth: CGFloat = 200
    static let idleHeight: CGFloat = 34
    static let toastExtraHeight: CGFloat = 32
    static let toastDuration: Double = 1.8
    static let fallbackMenuBarHeight: CGFloat = 24
    static let expandedWidth: CGFloat = 560
    static let expandedMaxHeight: CGFloat = 480
    static let cardWidth: CGFloat = 150
    static let cardImageHeight: CGFloat = 130
}
