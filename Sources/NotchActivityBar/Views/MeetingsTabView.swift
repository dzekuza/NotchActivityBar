import SwiftUI

struct MeetingsTabView: View {
    let controller: MeetingRecorderController
    var searchText: String = ""

    @State private var expandedSessionID: UUID?

    private let liveTranscriptBottomID = "live-transcript-bottom"

    /// Looked up by id rather than held by value: `requestSummary` patches
    /// `pastSessions` asynchronously, so an AI summary that lands while the
    /// overlay is open still shows up in it.
    private var expandedSession: MeetingSession? {
        guard let expandedSessionID else { return nil }
        return controller.pastSessions.first { $0.id == expandedSessionID }
    }

    private var filteredSessions: [MeetingSession] {
        guard !searchText.isEmpty else { return controller.pastSessions }
        return controller.pastSessions.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.transcript.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if controller.isRecording {
                liveCard
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let error = controller.lastError {
                banner(error, tint: Theme.danger, icon: "exclamationmark.octagon.fill", fix: missingPermission)
            }

            // A recording that started but can only hear our own side is still a
            // half-lost meeting, so it gets said out loud here rather than only
            // in the log.
            if let warning = controller.lastWarning {
                banner(warning, tint: Theme.amber, icon: "exclamationmark.triangle.fill", fix: missingPermission)
            }

            MeetingCardScrollView(sessions: filteredSessions, isSearching: !searchText.isEmpty, onDelete: { session in
                controller.deleteSession(session)
                if expandedSessionID == session.id { expandedSessionID = nil }
            }, onExpand: { session in
                expandedSessionID = session.id
            })
        }
        .animation(.easeInOut(duration: 0.2), value: controller.isRecording)
        .animation(.easeInOut(duration: 0.2), value: controller.lastError)
        .animation(.easeInOut(duration: 0.2), value: controller.lastWarning)
        .padding(.bottom, 16)
        .overlay {
            if let session = expandedSession {
                MeetingDetailOverlay(
                    session: session,
                    onDelete: {
                        controller.deleteSession(session)
                        expandedSessionID = nil
                    },
                    onClose: { expandedSessionID = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.snappy(duration: 0.2), value: expandedSessionID)
    }

    /// The first permission standing between the user and a complete recording,
    /// so a failure banner can offer the fix instead of just naming the pane.
    private var missingPermission: PermissionsController.Kind? {
        controller.permissions.blockingIssues.first
    }

    private func banner(
        _ message: String,
        tint: Color,
        icon: String,
        fix: PermissionsController.Kind?
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let fix {
                Button {
                    controller.permissions.request(fix)
                } label: {
                    Text(controller.permissions.status(for: fix) == .notDetermined ? "Allow…" : "Open Settings…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.inactiveTabBackground))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Grant \(fix.title) access")
            }
        }
        .padding(.horizontal, 20)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(controller.isAutoDetectEnabled ? Theme.amber : Theme.tertiaryText)
                .frame(width: 6, height: 6)
            Text(controller.isAutoDetectEnabled ? "Auto-recording calls" : "Auto-detect off")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondaryText)

            Spacer()

            Button(controller.isRecording ? "Stop" : "Record Now") {
                withAnimation(.snappy(duration: 0.2)) {
                    controller.toggleManually()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(controller.isRecording ? Theme.danger : Theme.primaryText)
            .contentTransition(.interpolate)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.inactiveTabBackground))
            .animation(.snappy(duration: 0.2), value: controller.isRecording)
        }
        .padding(.horizontal, 20)
    }

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.danger)
                    .frame(width: 8, height: 8)
                Text("Recording…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.danger)
            }

            if controller.liveSegments.isEmpty {
                TranscribingIndicatorView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Pinned to a fixed height and scrolled to the newest turn: the
                // live transcript grows without bound, and anything that feeds
                // the panel's measured height would restart the window resize
                // animation on every recognized word.
                ScrollViewReader { proxy in
                    ScrollView {
                        TranscriptSegmentsView(
                            segments: controller.liveSegments,
                            textSize: 12,
                            isSelectable: false
                        )
                        .padding(.trailing, 4)
                        .id(liveTranscriptBottomID)
                    }
                    .frame(height: 76)
                    .onChange(of: controller.liveSegments) {
                        proxy.scrollTo(liveTranscriptBottomID, anchor: .bottom)
                    }
                }
            }
        }
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .padding(.horizontal, 20)
    }
}
