import AppKit
import SwiftUI

struct NoteCardView: View {
    let note: NoteItem
    let onDelete: () -> Void
    var onExpand: () -> Void = {}

    @State private var isHovering = false
    @State private var showCopiedConfirmation = false

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
                .overlay(alignment: .bottomTrailing) {
                    if isHovering {
                        HStack(spacing: 6) {
                            if showCopiedConfirmation {
                                Text("Copied")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Theme.overlayChipBackground))
                                    .transition(.opacity)
                            }
                            Button(action: copyToClipboard) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(Theme.overlayChipBackground))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Copy note")
                            Button(action: onExpand) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(Theme.overlayChipBackground))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Expand note")
                        }
                        .padding(6)
                        .transition(.opacity)
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
                .accessibilityLabel("Delete note")
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture(perform: onExpand)
        .contextMenu {
            Button("Copy", action: copyToClipboard)
            Button("Open", action: onExpand)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(note.text, forType: .string)

        showCopiedConfirmation = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            showCopiedConfirmation = false
        }
    }
}
