import Observation

@MainActor
@Observable
final class NotesController {
    private(set) var notes: [NoteItem] = []

    init() {
        notes = NotesStore.load().sorted { $0.createdAt > $1.createdAt }
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        notes.insert(NoteItem(text: trimmed), at: 0)
        persist()
    }

    func delete(_ note: NoteItem) {
        notes.removeAll { $0.id == note.id }
        persist()
    }

    func clear() {
        notes.removeAll()
        persist()
    }

    private func persist() {
        NotesStore.save(notes)
    }
}
