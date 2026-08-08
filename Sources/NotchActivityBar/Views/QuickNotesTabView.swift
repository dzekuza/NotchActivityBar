import SwiftUI

struct QuickNotesTabView: View {
    let controller: QuickNotesController

    @State private var composerText = ""
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            composer

            if controller.notes.isEmpty {
                EmptyStateView(
                    systemImage: "note.text",
                    title: "No notes yet",
                    subtitle: "Type above and press Return to save"
                )
                .frame(width: Theme.expandedWidth)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(controller.notes) { note in
                            QuickNoteCardView(note: note) { text in
                                controller.update(note, text: text)
                            } onDelete: {
                                controller.delete(note)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .scrollIndicators(.never)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 16)
        .frame(height: Theme.cardImageHeight + 160, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.amber)
            Text("\(controller.notes.count) note\(controller.notes.count == 1 ? "" : "s")")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Write a quick note and press Return…", text: $composerText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.primaryText)
                .focused($isComposerFocused)
                .onSubmit(commitComposer)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous))

            Button(action: commitComposer) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isComposerEmpty ? Theme.tertiaryText : Theme.amber)
            }
            .buttonStyle(.plain)
            .disabled(isComposerEmpty)
        }
        .padding(.horizontal, 20)
    }

    private var isComposerEmpty: Bool {
        composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func commitComposer() {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        controller.add(text: trimmed)
        composerText = ""
        isComposerFocused = true
    }
}

private struct QuickNoteCardView: View {
    let note: QuickNote
    let onCommit: (String) -> Void
    let onDelete: () -> Void

    @State private var draft: String
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    init(note: QuickNote, onCommit: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        self.note = note
        self.onCommit = onCommit
        self.onDelete = onDelete
        _draft = State(initialValue: note.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $draft)
                .font(.system(size: 12))
                .foregroundStyle(Theme.primaryText)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(width: Theme.cardWidth, height: Theme.cardImageHeight)
                .fixedSize(horizontal: false, vertical: false)
                .clipped()
                .focused($isFocused)
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty && !isFocused {
                        Text("Write a note…")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.tertiaryText)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Text("Note")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.primaryText.opacity(0.85))
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
                .strokeBorder(Color.white.opacity(isFocused ? 0.22 : (isHovering ? 0.16 : 0.06)), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if isHovering && !isFocused {
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
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .onChange(of: isFocused) { wasFocused, focused in
            if wasFocused && !focused {
                onCommit(draft)
            }
        }
    }
}
