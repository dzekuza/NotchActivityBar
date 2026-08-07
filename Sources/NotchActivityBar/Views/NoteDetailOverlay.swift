import SwiftUI

struct NoteDetailOverlay: View {
    let note: NoteItem
    let onDelete: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Theme.modalScrim
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Text(note.relativeTime)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                    Spacer()
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.danger)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Theme.overlayButtonBackground))
                    }
                    .buttonStyle(.plain)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Theme.overlayButtonBackground))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                ScrollView {
                    Text(note.text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
                .frame(maxHeight: min(Theme.expandedMaxHeight - 80, 320))
            }
            .frame(width: Theme.expandedWidth - 120)
            .background(Theme.panelBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.cardBorderHover, lineWidth: 1)
            }
        }
    }
}
