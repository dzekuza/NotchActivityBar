import AppKit
import SwiftUI

struct ExpandedPanelView: View {
    let clipboardMonitor: ClipboardMonitor
    let screenshotMonitor: ScreenshotMonitor
    let privacyGuardController: PrivacyGuardController
    let meetingRecorderController: MeetingRecorderController
    let notesController: NotesController
    @Binding var selectedTab: AppTab
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SearchBarView(
                text: $searchText,
                onClearAll: clearActiveTab,
                isPrivacyMuted: privacyGuardController.isMuted,
                cameraAccessDenied: privacyGuardController.cameraAccessDenied,
                isRecording: meetingRecorderController.isRecording,
                onToggleRecording: { meetingRecorderController.toggleManually() },
                onTogglePrivacyMute: privacyGuardController.toggle
            )
            persistentLiveBanner
            TabPillBarView(selection: $selectedTab, counts: [
                .clipboard: clipboardMonitor.items.count,
                .screenshots: screenshotMonitor.items.count,
                .meetings: meetingRecorderController.pastSessions.count,
                .notes: notesController.notes.count,
            ])
            content
        }
        .frame(width: Theme.expandedWidth)
        .background(
            Theme.panelBackground,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: Theme.panelCornerRadius,
                bottomTrailingRadius: Theme.panelCornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.height, initial: true) { _, newValue in
                        onHeightChange(newValue)
                    }
            }
        }
    }

    @ViewBuilder
    private var persistentLiveBanner: some View {
        if meetingRecorderController.isRecording && selectedTab != .meetings {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.danger)
                    .frame(width: 7, height: 7)
                if meetingRecorderController.activeTranscriber?.transcript.isEmpty ?? true {
                    TranscribingIndicatorView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(meetingRecorderController.activeTranscriber?.transcript ?? "")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button("Stop") {
                    meetingRecorderController.toggleManually()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.danger)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.danger.opacity(0.18)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .clipboard:
            ClipboardCardScrollView(items: filteredClipboardItems) { item in
                clipboardMonitor.copy(item)
            } onDelete: { item in
                clipboardMonitor.delete(item)
            }
        case .screenshots:
            ScreenshotCardScrollView(items: filteredScreenshotItems) { item in
                screenshotMonitor.delete(item)
            }
        case .meetings:
            MeetingsTabView(controller: meetingRecorderController)
        case .notes:
            NotesTabView(controller: notesController)
        case .settings:
            SettingsTabView()
        }
    }

    private var filteredClipboardItems: [ClipboardItem] {
        guard !searchText.isEmpty else { return clipboardMonitor.items }
        return clipboardMonitor.items.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.subtitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredScreenshotItems: [ScreenshotItem] {
        guard !searchText.isEmpty else { return screenshotMonitor.items }
        return screenshotMonitor.items.filter { $0.appName.localizedCaseInsensitiveContains(searchText) }
    }

    private func clearActiveTab() {
        switch selectedTab {
        case .clipboard:
            clipboardMonitor.clear()
        case .notes:
            notesController.clear()
        case .screenshots, .meetings, .settings:
            break
        }
    }
}
