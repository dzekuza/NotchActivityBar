import Foundation

/// Persists meeting transcripts as JSON files under Application Support.
///
/// Not `@MainActor`-isolated on purpose: every method here does blocking
/// `FileManager`/`JSONEncoder`/`JSONDecoder` work, and callers on the main
/// actor `await` them so that work runs on the background executor instead
/// of stalling the UI (most importantly `loadAll()`, which decodes every
/// stored session at app launch).
enum MeetingSessionStore {
    /// Keeps the on-disk session history from growing unbounded — auto-detect
    /// can false-positive on any mic use, so every completed call gets a
    /// permanent file with no other eviction path. Oldest sessions beyond this
    /// count are pruned during `loadAll()`.
    private static let maxRetainedSessions = 200

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("NotchActivityBar/Meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func save(_ session: MeetingSession) async {
        let url = directory.appendingPathComponent("\(session.id.uuidString).json")
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadAll() async -> [MeetingSession] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        let sessions = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> MeetingSession? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(MeetingSession.self, from: data)
            }
            .sorted { $0.startedAt > $1.startedAt }

        guard sessions.count > maxRetainedSessions else { return sessions }
        for stale in sessions[maxRetainedSessions...] {
            let url = directory.appendingPathComponent("\(stale.id.uuidString).json")
            try? FileManager.default.removeItem(at: url)
        }
        return Array(sessions.prefix(maxRetainedSessions))
    }

    static func delete(_ session: MeetingSession) async {
        let url = directory.appendingPathComponent("\(session.id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }
}
