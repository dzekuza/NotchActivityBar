import Foundation
import Observation

/// Polls `claude agents --all --json` — Claude Code's own scriptable listing
/// of every interactive/background session on this machine — and groups the
/// results by project directory. Read-only: this app has no control over
/// these sessions, it only observes them.
@MainActor
@Observable
final class ClaudeAgentsOverviewMonitor {
    private(set) var projectGroups: [(cwd: String, agents: [ClaudeAgentSummary])] = []
    private(set) var lastError: String?

    private var timer: Timer?
    private let pollInterval: TimeInterval = 5.0
    private var claudePath: String?
    private var isPolling = false

    func start(claudePath: String) {
        self.claudePath = claudePath
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard !isPolling, let claudePath else { return }
        isPolling = true
        Task.detached(priority: .utility) { [weak self, claudePath] in
            let outcome: Result<[ClaudeAgentSummary], Error>
            do {
                outcome = .success(try Self.fetchAgents(claudePath: claudePath))
            } catch {
                outcome = .failure(error)
            }
            await MainActor.run {
                guard let self else { return }
                self.isPolling = false
                switch outcome {
                case .success(let summaries):
                    self.lastError = nil
                    self.projectGroups = Dictionary(grouping: summaries, by: \.cwd)
                        .map { (cwd: $0.key, agents: $0.value.sorted { $0.startedAt > $1.startedAt }) }
                        .sorted { ($0.agents.first?.startedAt ?? 0) > ($1.agents.first?.startedAt ?? 0) }
                case .failure(let error):
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    private nonisolated static func fetchAgents(claudePath: String) throws -> [ClaudeAgentSummary] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["agents", "--all", "--json"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        try process.run()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return try JSONDecoder().decode([ClaudeAgentSummary].self, from: data)
    }
}
