import Foundation

/// Persists quick notes as JSON files under Application Support.
enum QuickNoteStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("NotchActivityBar/Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func save(_ note: QuickNote) {
        let url = directory.appendingPathComponent("\(note.id.uuidString).json")
        guard let data = try? JSONEncoder().encode(note) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadAll() -> [QuickNote] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        let notes = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> QuickNote? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(QuickNote.self, from: data)
            }
        return notes.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func delete(_ note: QuickNote) {
        let url = directory.appendingPathComponent("\(note.id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }
}
