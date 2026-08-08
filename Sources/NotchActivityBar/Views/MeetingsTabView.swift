import AppKit
import SwiftUI

struct MeetingsTabView: View {
    let controller: MeetingRecorderController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

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
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        if controller.isRecording {
                            liveCard
                        }
                        ForEach(controller.pastSessions) { session in
                            MeetingSessionCardView(session: session) {
                                controller.deleteSession(session)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .scrollIndicators(.never)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 16)
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
        VStack(alignment: .leading, spacing: 0) {
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
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.primaryText.opacity(0.9))
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
            .frame(width: Theme.cardWidth, height: Theme.cardImageHeight, alignment: .topLeading)
        }
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.danger.opacity(0.35), lineWidth: 1)
        }
    }
}

private struct MeetingSessionCardView: View {
    let session: MeetingSession
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                Text(session.transcript.isEmpty ? "No transcript" : session.transcript)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.primaryText.opacity(0.9))
                    .lineLimit(4)
            }
            .padding(10)
            .frame(width: Theme.cardWidth, height: Theme.cardImageHeight, alignment: .topLeading)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: Theme.cardCornerRadius,
                    topTrailingRadius: Theme.cardCornerRadius,
                    style: .continuous
                )
            )

            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Text(session.durationLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.primaryText.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if justCopied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.amber)
                } else {
                    Text(session.title)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: Theme.cardWidth, alignment: .leading)
        }
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(isHovering ? 0.16 : 0.06), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.black.opacity(0.65)))
                }
                .buttonStyle(.plain)
                .padding(6)
                .transition(.opacity)
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture { copyTranscript() }
        .help("Copy transcript")
    }

    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.transcript, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { justCopied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            withAnimation(.easeOut(duration: 0.15)) { justCopied = false }
        }
    }
}
