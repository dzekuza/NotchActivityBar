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
        if let notes = try? JSONDecoder().decode([NoteItem].self, from: data) {
            return notes
        }
        // Decoding failed (partial write, disk corruption, unreadable future
        // format, etc.) — preserve the unreadable file instead of letting the
        // next `save()` silently overwrite it with an empty array.
        let backupURL = fileURL.deletingPathExtension().appendingPathExtension("corrupted.json")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.copyItem(at: fileURL, to: backupURL)
        NSLog("NotesStore: failed to decode \(fileURL.path) — backed up to \(backupURL.path)")
        return []
    }

    static func save(_ notes: [NoteItem]) {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
