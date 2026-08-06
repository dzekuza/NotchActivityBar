import AppKit

struct NotchGeometry {
    let width: CGFloat
    let height: CGFloat
    let hasPhysicalNotch: Bool

    static func resolve(for screen: NSScreen) -> NotchGeometry {
        let topInset = screen.safeAreaInsets.top

        guard topInset > 0,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea
        else {
            return NotchGeometry(
                width: Theme.idleWidth,
                height: Theme.fallbackMenuBarHeight,
                hasPhysicalNotch: false
            )
        }

        let notchWidth = screen.frame.width - leftArea.width - rightArea.width
        return NotchGeometry(
            width: max(notchWidth, Theme.idleWidth),
            height: topInset,
            hasPhysicalNotch: true
        )
    }
}
