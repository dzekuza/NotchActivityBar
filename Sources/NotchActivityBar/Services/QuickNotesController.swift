import Foundation
import Observation

@MainActor
@Observable
final class QuickNotesController {
    private(set) var notes: [QuickNote] = []

    init() {
        notes = QuickNoteStore.loadAll()
    }

    @discardableResult
    func add(text: String = "") -> QuickNote {
        let note = QuickNote(text: text)
        notes.insert(note, at: 0)
        QuickNoteStore.save(note)
        return note
    }

    func update(_ note: QuickNote, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].text = text
        notes[index].updatedAt = Date()
        QuickNoteStore.save(notes[index])
    }

    func delete(_ note: QuickNote) {
        notes.removeAll { $0.id == note.id }
        QuickNoteStore.delete(note)
    }

    func clear() {
        notes.forEach(QuickNoteStore.delete)
        notes.removeAll()
    }
}
