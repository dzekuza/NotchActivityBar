import SwiftUI

struct NoteCardView: View {
    let note: NoteItem
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Theme.cardBackground
                .overlay(alignment: .topLeading) {
                    Text(note.text)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(5)
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
                Image(systemName: "note.text")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Text("Note")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.primaryText.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(note.relativeTime)
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
    }
}
