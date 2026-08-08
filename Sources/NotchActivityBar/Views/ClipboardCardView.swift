import SwiftUI

struct ClipboardCardView: View {
    let item: ClipboardItem
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            contentArea
                .frame(width: Theme.cardWidth, height: Theme.cardImageHeight)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: Theme.cardCornerRadius,
                        topTrailingRadius: Theme.cardCornerRadius,
                        style: .continuous
                    )
                )

            HStack(spacing: 6) {
                Image(systemName: item.iconSystemName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Text(metaLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.primaryText.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if justCopied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.amber)
                } else {
                    Text(item.relativeTime)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
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
        .onTapGesture { copy() }
    }

    @ViewBuilder
    private var contentArea: some View {
        switch item.kind {
        case .color:
            (item.swatchColor ?? Theme.cardBackground)
                .overlay(alignment: .topLeading) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(10)
                }
        case .image:
            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Theme.cardWidth, height: Theme.cardImageHeight)
                    .clipped()
            } else {
                Theme.cardBackground
                    .overlay { Image(systemName: "photo").foregroundStyle(Theme.tertiaryText) }
            }
        case .link:
            if let url = item.linkURL {
                LinkPreviewView(url: url)
                    .frame(width: Theme.cardWidth, height: Theme.cardImageHeight)
                    .background(Theme.cardBackground)
            } else {
                Theme.cardBackground
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "link")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.amber)
                            Text(item.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(3)
                        }
                        .padding(10)
                    }
            }
        case .text:
            Theme.cardBackground
                .overlay(alignment: .topLeading) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(5)
                        .padding(10)
                }
        }
    }

    private var metaLabel: String {
        item.folder.rawValue
    }

    private func copy() {
        onCopy()
        withAnimation(.easeOut(duration: 0.15)) { justCopied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            withAnimation(.easeOut(duration: 0.15)) { justCopied = false }
        }
    }
}
