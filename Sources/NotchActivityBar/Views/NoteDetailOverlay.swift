import AppKit
import SwiftUI

struct NoteDetailOverlay: View {
    let note: NoteItem
    let onDelete: () -> Void
    let onClose: () -> Void
    let onSave: (String) -> Void

    @State private var showCopiedConfirmation = false
    @State private var isEditing: Bool
    @State private var editedText: String
    @FocusState private var isEditorFocused: Bool

    init(note: NoteItem, onDelete: @escaping () -> Void, onClose: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.note = note
        self.onDelete = onDelete
        self.onClose = onClose
        self.onSave = onSave
        // Opening a single note goes straight into editing — there's no
        // separate "view" step, the note's text just starts out selected
        // for typing.
        _isEditing = State(initialValue: true)
        _editedText = State(initialValue: note.text)
    }

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
                    if showCopiedConfirmation {
                        Text("Copied")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .transition(.opacity)
                    }
                    if isEditing {
                        Button("Cancel") { isEditing = false }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                        Button("Save", action: save)
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.tertiaryText : Theme.primaryText)
                            .disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button(action: beginEditing) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.primaryText)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Theme.overlayButtonBackground))
                        }
                        .buttonStyle(.plain)
                        Button(action: copyToClipboard) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.primaryText)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Theme.overlayButtonBackground))
                        }
                        .buttonStyle(.plain)
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
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                if isEditing {
                    TextEditor(text: $editedText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .scrollContentBackground(.hidden)
                        .focused($isEditorFocused)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .frame(maxHeight: min(Theme.expandedMaxHeight - 80, 320))
                        .onAppear { isEditorFocused = true }
                } else {
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
            }
            .frame(width: Theme.expandedWidth - 120)
            .background(Theme.panelBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.cardBorderHover, lineWidth: 1)
            }
        }
        .animation(.easeOut(duration: 0.15), value: showCopiedConfirmation)
    }

    private func beginEditing() {
        editedText = note.text
        isEditing = true
        isEditorFocused = true
    }

    private func save() {
        let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        isEditing = false
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
