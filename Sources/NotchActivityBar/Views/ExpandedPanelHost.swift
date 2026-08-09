import SwiftUI

struct ExpandedPanelHost: View {
    let clipboardMonitor: ClipboardMonitor
    let screenshotMonitor: ScreenshotMonitor
    let privacyGuardController: PrivacyGuardController
    let meetingRecorderController: MeetingRecorderController
    let notesController: NotesController
    let claudeSessionsController: ClaudeSessionsController
    let onHeightChange: (CGFloat) -> Void

    @State private var selectedTab: AppTab = .clipboard

    var body: some View {
        ExpandedPanelView(
            clipboardMonitor: clipboardMonitor,
            screenshotMonitor: screenshotMonitor,
            privacyGuardController: privacyGuardController,
            meetingRecorderController: meetingRecorderController,
            notesController: notesController,
            claudeSessionsController: claudeSessionsController,
            selectedTab: $selectedTab,
            onHeightChange: onHeightChange
        )
        .onChange(of: meetingRecorderController.isRecording) { _, isRecording in
            if isRecording {
                selectedTab = .meetings
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .claudeSessions {
                claudeSessionsController.start()
            }
        }
    }
}
