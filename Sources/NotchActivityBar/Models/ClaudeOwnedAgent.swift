import Foundation
import Observation

enum ClaudeAgentState: Equatable {
    case starting
    case running
    case waitingForInput
    case exited(code: Int32)
    case failed(String)
}

struct ClaudeTranscriptTurn: Identifiable, Equatable {
    enum Role: Equatable {
        case user, assistant, tool
    }

    let id = UUID()
    let role: Role
    var text: String
}

/// A tool-permission request surfaced by the running agent's `PreToolUse`
/// hook, waiting on an accept/decline decision from this app. `id` is the
/// bridge's own correlation id (see `ClaudePermissionBridge`), not Claude's
/// `tool_use_id`.
struct ClaudePermissionRequest: Identifiable, Equatable {
    let id: String
    let toolName: String
    let inputSummary: String
}

/// An agent this app spawned and fully owns the process/pipes for — as
/// opposed to `ClaudeAgentSummary`, which only describes sessions already
/// running elsewhere that this app can see but not control.
@MainActor
@Observable
final class ClaudeOwnedAgent: Identifiable {
    let id = UUID()
    let projectPath: String
    var claudeSessionId: String?
    var turns: [ClaudeTranscriptTurn] = []
    var pendingPermission: ClaudePermissionRequest?
    var state: ClaudeAgentState = .starting

    init(projectPath: String) {
        self.projectPath = projectPath
    }

    var projectName: String {
        (projectPath as NSString).lastPathComponent
    }
}
