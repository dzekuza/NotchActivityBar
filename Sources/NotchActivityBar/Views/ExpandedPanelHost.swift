import SwiftUI

struct ExpandedPanelHost: View {
    let clipboardMonitor: ClipboardMonitor
    let screenshotMonitor: ScreenshotMonitor
    let onHoverChange: (Bool) -> Void
    let onHeightChange: (CGFloat) -> Void

    @State private var selectedTab: AppTab = .clipboard

    var body: some View {
        ExpandedPanelView(
            clipboardMonitor: clipboardMonitor,
            screenshotMonitor: screenshotMonitor,
            selectedTab: $selectedTab,
            onHeightChange: onHeightChange
        )
        .onHover(perform: onHoverChange)
    }
}
