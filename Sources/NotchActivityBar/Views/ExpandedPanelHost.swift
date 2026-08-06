import SwiftUI

struct ExpandedPanelHost: View {
    let clipboardMonitor: ClipboardMonitor
    let screenshotMonitor: ScreenshotMonitor
    let privacyGuardController: PrivacyGuardController
    let meetingRecorderController: MeetingRecorderController
    let geminiAPIKeyStore: GeminiAPIKeyStore
    let onHoverChange: (Bool) -> Void
    let onHeightChange: (CGFloat) -> Void

    @State private var selectedTab: AppTab = .clipboard

    var body: some View {
        ExpandedPanelView(
            clipboardMonitor: clipboardMonitor,
            screenshotMonitor: screenshotMonitor,
            privacyGuardController: privacyGuardController,
            meetingRecorderController: meetingRecorderController,
            geminiAPIKeyStore: geminiAPIKeyStore,
            selectedTab: $selectedTab,
            onHeightChange: onHeightChange
        )
        .onHover(perform: onHoverChange)
        .onChange(of: meetingRecorderController.isRecording) { _, isRecording in
            if isRecording {
                selectedTab = .meetings
            }
        }
    }
}
