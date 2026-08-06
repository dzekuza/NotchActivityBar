import Foundation

/// Persists meeting transcripts as JSON files under Application Support.
enum MeetingSessionStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("NotchActivityBar/Meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func save(_ session: MeetingSession) {
        let url = directory.appendingPathComponent("\(session.id.uuidString).json")
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadAll() -> [MeetingSession] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        let sessions = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> MeetingSession? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(MeetingSession.self, from: data)
            }
        return sessions.sorted { $0.startedAt > $1.startedAt }
    }

    static func delete(_ session: MeetingSession) {
        let url = directory.appendingPathComponent("\(session.id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }
}
