import SwiftUI

struct NotesTabView: View {
    let controller: NotesController
    var searchText: String = ""

    @State private var draft = ""
    @State private var expandedNote: NoteItem?
    @FocusState private var isInputFocused: Bool

    private var filteredNotes: [NoteItem] {
        guard !searchText.isEmpty else { return controller.notes }
        return controller.notes.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            inputRow
            NoteCardScrollView(notes: filteredNotes, isSearching: !searchText.isEmpty) { note in
                controller.delete(note)
                if expandedNote?.id == note.id { expandedNote = nil }
            } onExpand: { note in
                expandedNote = note
            }
        }
        .padding(.bottom, 16)
        .overlay {
            if let note = expandedNote {
                NoteDetailOverlay(
                    note: note,
                    onDelete: {
                        controller.delete(note)
                        expandedNote = nil
                    },
                    onClose: { expandedNote = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.snappy(duration: 0.2), value: expandedNote)
    }

    private var inputRow: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("Quick note…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 15)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $draft)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.primaryText)
                    .scrollContentBackground(.hidden)
                    .focused($isInputFocused)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        commit()
                        return .handled
                    }
            }
            .frame(height: 64)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous))

            HStack(spacing: 6) {
                Text("⌘⏎ to save")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
                Button("Add", action: commit)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.tertiaryText : Theme.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.inactiveTabBackground))
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 20)
    }

    private func commit() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        controller.add(draft)
        draft = ""
        isInputFocused = true
    }
}
