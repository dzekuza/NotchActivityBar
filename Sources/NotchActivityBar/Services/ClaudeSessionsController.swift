import Foundation
import Observation

/// Orchestrator for the Claude tab: a read-only live view of every Claude
/// Code session on this machine (`overviewMonitor`), plus full control
/// (chat + permission accept/decline) over agents this app spawns itself
/// (`ownedAgents`) — see `ClaudeOwnedAgent` for why those are two different
/// things.
@MainActor
@Observable
final class ClaudeSessionsController {
    let overviewMonitor = ClaudeAgentsOverviewMonitor()
    private(set) var ownedAgents: [ClaudeOwnedAgent] = []
    private(set) var claudeAvailable = true
    private(set) var isResolvingCLI = false

    private var claudePath: String?
    private var processes: [UUID: ClaudeAgentProcess] = [:]
    private var bridges: [UUID: ClaudePermissionBridge] = [:]
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        isResolvingCLI = true
        Task.detached(priority: .utility) { [weak self] in
            let path = ClaudeCLIAvailability.resolvePath()
            await MainActor.run {
                guard let self else { return }
                self.isResolvingCLI = false
                self.claudePath = path
                self.claudeAvailable = path != nil
                if let path {
                    self.overviewMonitor.start(claudePath: path)
                }
            }
        }
    }

    func stop() {
        overviewMonitor.stop()
        for agent in ownedAgents {
            processes[agent.id]?.terminate()
            bridges[agent.id]?.cleanUp()
        }
        processes.removeAll()
        bridges.removeAll()
    }

    func startAgent(projectPath: String, firstMessage: String) {
        guard let claudePath else { return }

        let agent = ClaudeOwnedAgent(projectPath: projectPath)
        agent.turns.append(ClaudeTranscriptTurn(role: .user, text: firstMessage))
        ownedAgents.insert(agent, at: 0)

        let bridge = ClaudePermissionBridge(agentID: agent.id)
        bridge.onRequest = { [weak agent] request in
            guard let agent else { return }
            agent.pendingPermission = request
        }
        bridges[agent.id] = bridge

        let process = ClaudeAgentProcess()
        process.onEvent = { [weak self, weak agent] event in
            self?.handle(event: event, for: agent)
        }
        process.onExit = { [weak self, weak agent] code in
            guard let self, let agent else { return }
            agent.state = .exited(code: code)
            self.cleanUp(agentID: agent.id)
        }
        processes[agent.id] = process

        do {
            let settingsURL = try bridge.writeSettingsFile()
            bridge.start()
            try process.start(claudePath: claudePath, projectPath: projectPath, settingsPath: settingsURL.path)
            agent.state = .running
            process.send(userText: firstMessage)
        } catch {
            agent.state = .failed(error.localizedDescription)
            cleanUp(agentID: agent.id)
        }
    }

    func send(_ text: String, to agent: ClaudeOwnedAgent) {
        guard let process = processes[agent.id], agent.pendingPermission == nil else { return }
        agent.turns.append(ClaudeTranscriptTurn(role: .user, text: text))
        agent.state = .running
        process.send(userText: text)
    }

    func respondToPermission(_ agent: ClaudeOwnedAgent, allow: Bool) {
        guard let pending = agent.pendingPermission, let bridge = bridges[agent.id] else { return }
        bridge.respond(id: pending.id, allow: allow)
        agent.pendingPermission = nil
        agent.state = .running
    }

    func stopAgent(_ agent: ClaudeOwnedAgent) {
        processes[agent.id]?.terminate()
        agent.state = .exited(code: 0)
        cleanUp(agentID: agent.id)
    }

    /// Drops a finished agent's card. Terminates first in case it's still
    /// alive — `stopAgent` and this are the only ways a card leaves the list,
    /// and a removed card must not leave an orphaned subprocess behind.
    func removeAgent(_ agent: ClaudeOwnedAgent) {
        processes[agent.id]?.terminate()
        cleanUp(agentID: agent.id)
        ownedAgents.removeAll { $0.id == agent.id }
    }

    private func cleanUp(agentID: UUID) {
        processes[agentID] = nil
        bridges[agentID]?.cleanUp()
        bridges[agentID] = nil
    }

    private func handle(event: ClaudeStreamEvent, for agent: ClaudeOwnedAgent?) {
        guard let agent else { return }
        switch event {
        case .initInfo(let sessionId):
            agent.claudeSessionId = sessionId
        case .assistantText(let text):
            agent.turns.append(ClaudeTranscriptTurn(role: .assistant, text: text))
        case .toolUse(_, let name, let inputSummary):
            agent.turns.append(ClaudeTranscriptTurn(role: .tool, text: "\(name)(\(inputSummary))"))
        case .finalResult:
            if agent.pendingPermission == nil, case .running = agent.state {
                agent.state = .waitingForInput
            }
        case .unknown:
            break
        }
    }
}
