import Foundation

/// Mirrors one entry from `claude agents --all --json` — a live interactive
/// or background Claude Code session already running somewhere on this
/// machine, keyed by `sessionId`. Read-only; this app has no control over
/// sessions it didn't spawn itself (see `ClaudeOwnedAgent`).
struct ClaudeAgentSummary: Decodable, Identifiable, Equatable {
    let pid: Int?
    let cwd: String
    let kind: String
    let status: String?
    let state: String?
    let name: String?
    let sessionId: String
    let startedAt: Double

    var id: String { sessionId }

    var isBackground: Bool { kind == "background" }

    var displayStatus: String {
        status ?? state ?? "running"
    }

    var startedDate: Date {
        Date(timeIntervalSince1970: startedAt / 1000)
    }
}
