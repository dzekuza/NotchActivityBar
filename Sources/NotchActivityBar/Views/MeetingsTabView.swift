import SwiftUI

struct MeetingsTabView: View {
    let controller: MeetingRecorderController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if controller.isRecording {
                liveCard
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let error = controller.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            MeetingCardScrollView(sessions: controller.pastSessions) { session in
                controller.deleteSession(session)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controller.isRecording)
        .animation(.easeInOut(duration: 0.2), value: controller.lastError)
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
