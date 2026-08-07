import Foundation

/// Persists quick notes as a single JSON file under Application Support.
enum NotesStore {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("NotchActivityBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Notes.json")
    }

    static func load() -> [NoteItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([NoteItem].self, from: data)) ?? []
    }

    static func save(_ notes: [NoteItem]) {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
