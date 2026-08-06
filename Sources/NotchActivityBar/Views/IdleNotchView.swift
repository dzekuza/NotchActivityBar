import SwiftUI

struct IdleNotchView: View {
    var size: CGSize = CGSize(width: Theme.idleWidth, height: Theme.idleHeight)
    var cornerRadius: CGFloat = 14
    var toast: NotchToast?
    var isRecording: Bool = false
    var liveTranscript: String = ""
    var onStopRecording: () -> Void = {}

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: cornerRadius,
            topTrailingRadius: 0,
            style: .continuous
        )
        .fill(Theme.panelBackground)
        .overlay(alignment: .center) {
            Circle()
                .fill(Theme.amber)
                .frame(width: 6, height: 6)
                .shadow(color: Theme.amber.opacity(0.6), radius: 4)
                .opacity(toast == nil && !isRecording ? 1 : 0)
        }
        .overlay(alignment: .bottom) {
            // A transient toast takes priority; the recording banner persists
            // underneath it and reappears when the toast fades.
            if let toast {
                HStack(spacing: 6) {
                    Image(systemName: toast.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                    Text(toast.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                }
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if isRecording {
                HStack(spacing: 8) {
                    PulsingRecordDot()
                    Text(liveTranscript.isEmpty ? "Recording…" : liveTranscript)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: onStopRecording) {
                        Text("Stop")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.danger)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.danger.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toast)
        .animation(.easeInOut(duration: 0.2), value: isRecording)
        .frame(width: size.width, height: size.height)
    }
}

private struct PulsingRecordDot: View {
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(Theme.danger)
            .frame(width: 7, height: 7)
            .shadow(color: Theme.danger.opacity(0.7), radius: 3)
            .opacity(dimmed ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: dimmed)
            .onAppear { dimmed = true }
    }
}
