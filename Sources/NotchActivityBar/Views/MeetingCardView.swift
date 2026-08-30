import SwiftUI

struct MeetingCardView: View {
    let session: MeetingSession
    let onDelete: () -> Void
    let onExpand: () -> Void

    @State private var isHovering = false

    private var previewText: String {
        if let summary = session.summary, !summary.isEmpty {
            return summary
        }
        return session.transcript.isEmpty ? "No transcript" : session.transcript
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Theme.cardBackground
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.amber)
                        Text(previewText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(4)
                    }
                    .padding(10)
                }
                .frame(width: Theme.cardWidth, height: Theme.cardImageHeight)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: Theme.cardCornerRadius,
                        topTrailingRadius: Theme.cardCornerRadius,
                        style: .continuous
                    )
                )

            HStack(spacing: 6) {
                Text(session.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.primaryText.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(session.durationLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: Theme.cardWidth, alignment: .leading)
        }
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(isHovering ? Theme.cardBorderHover : Theme.cardBorderDefault, lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Theme.overlayChipBackground))
                }
                .buttonStyle(.plain)
                .padding(6)
                .transition(.opacity)
                .accessibilityLabel("Delete meeting")
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture(perform: onExpand)
        .contextMenu {
            Button("Open", action: onExpand)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
