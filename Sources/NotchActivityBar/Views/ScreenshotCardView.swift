import AppKit
import SwiftUI

struct ScreenshotCardView: View {
    let item: ScreenshotItem
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Theme.cardBackground
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ProgressView().controlSize(.small)
                }
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
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Text(item.appName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.primaryText.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(item.relativeTime)
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
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(item.url) }
        .draggable(item.url) {
            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Theme.cardWidth, height: Theme.cardImageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            }
        }
    }
}
