import SwiftUI

struct MeetingsTabView: View {
    let controller: MeetingRecorderController

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                header

                if controller.isRecording {
                    liveCard
                }

                if let error = controller.lastError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.danger)
                        .padding(.horizontal, 20)
                }

                if controller.pastSessions.isEmpty && !controller.isRecording {
                    EmptyStateView(
                        systemImage: "waveform",
                        title: "No meetings recorded yet",
                        subtitle: "Recording starts automatically when a call is detected"
                    )
                    .frame(width: Theme.expandedWidth)
                } else {
                    ForEach(controller.pastSessions) { session in
                        MeetingSessionRow(session: session) {
                            controller.deleteSession(session)
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .frame(height: Theme.cardImageHeight + 60)
        .scrollIndicators(.never)
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
                controller.toggleManually()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(controller.isRecording ? Theme.danger : Theme.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.inactiveTabBackground))
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

            if controller.activeTranscriber?.transcript.isEmpty ?? true {
                TranscribingIndicatorView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(controller.activeTranscriber?.transcript ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.primaryText.opacity(0.9))
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .padding(.horizontal, 20)
    }
}

private struct MeetingSessionRow: View {
    let session: MeetingSession
    let onDelete: () -> Void

    @State private var isExpanded = false
    @State private var isHovering = false
    @State private var showCopiedToast = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.amber)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(session.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text(session.durationLabel)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.tertiaryText)
                    }

                    Text(session.transcript)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(isExpanded ? nil : 2)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 4)

                HStack(spacing: 8) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(session.transcript, forType: .string)
                        showCopiedToast = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            showCopiedToast = false
                        }
                    } label: {
                        Image(systemName: showCopiedToast ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(showCopiedToast ? Theme.amber : Theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Copy transcript")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Delete meeting recording")

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
        .onHover { isHovering = $0 }
    }
}
