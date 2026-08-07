import SwiftUI

struct NotesTabView: View {
    let controller: NotesController

    @State private var draft = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            inputRow
            NoteCardScrollView(notes: controller.notes) { note in
                controller.delete(note)
            }
        }
        .padding(.bottom, 16)
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Quick note…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .onSubmit(commit)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous))

            Button("Add", action: commit)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.tertiaryText : Theme.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.inactiveTabBackground))
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
