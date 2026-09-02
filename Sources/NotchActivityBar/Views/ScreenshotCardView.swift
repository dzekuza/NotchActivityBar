import AppKit
import SwiftUI

struct ScreenshotCardView: View {
    let item: ScreenshotItem
    let extractionState: ScreenshotExtractionState?
    let onDelete: () -> Void
    let onExtractText: () -> Void

    @State private var isHovering = false
    @State private var didCopy = false

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
                HStack(spacing: 4) {
                    Button(action: copyImage) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Theme.overlayChipBackground))
                    }
                    .buttonStyle(.plain)
                    .help("Copy screenshot")
                    .accessibilityLabel("Copy screenshot")

                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Theme.overlayChipBackground))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete screenshot")
                }
                .padding(6)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            if isHovering || extractionState != nil {
                Button(action: onExtractText) {
                    Group {
                        if extractionState == .loading {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "text.viewfinder")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Theme.overlayChipBackground))
                }
                .buttonStyle(.plain)
                .padding(6)
                .transition(.opacity)
                .help("Extract text and links")
                .accessibilityLabel("Extract text and links")
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(item.url) }
        .animation(.easeOut(duration: 0.12), value: didCopy)
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

    /// Puts the picture itself on the pasteboard, with the file reference
    /// behind it. Order is the preference order pasting apps see: a chat or a
    /// document takes the image, while Finder and anything wanting a file
    /// still gets the original off disk rather than a re-encoded copy.
    private func copyImage() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var objects: [NSPasteboardWriting] = []
        if let image = NSImage(contentsOf: item.url) {
            objects.append(image)
        }
        objects.append(item.url as NSURL)
        pasteboard.writeObjects(objects)

        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            didCopy = false
        }
    }
}
