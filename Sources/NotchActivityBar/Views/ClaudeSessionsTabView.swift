import SwiftUI

struct ClaudeSessionsTabView: View {
    let controller: ClaudeSessionsController
    var searchText: String = ""

    @State private var newAgentProjectPath = ""
    @State private var newAgentPrompt = ""
    @State private var showingNewAgentForm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if !controller.claudeAvailable && !controller.isResolvingCLI {
                    Text("Claude CLI not found on PATH. Install it to use this tab.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.danger)
                        .padding(.horizontal, 20)
                }

                if showingNewAgentForm {
                    newAgentForm
                }

                if !controller.ownedAgents.isEmpty {
                    sectionHeader("Your agents")
                    VStack(spacing: 10) {
                        ForEach(controller.ownedAgents) { agent in
                            ClaudeOwnedAgentCard(controller: controller, agent: agent)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                sectionHeader("Running now")
                if filteredGroups.isEmpty {
                    Text("No active Claude Code sessions detected.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 20)
                } else {
                    VStack(spacing: 10) {
                        ForEach(filteredGroups, id: \.cwd) { group in
                            ClaudeProjectGroupCard(group: group)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 16)
        }
        // Shares the one content budget rather than its own magic number: at
        // the previous 360 this tab plus the panel chrome and the live
        // recording banner came to more than `Theme.expandedMaxHeight`, so the
        // panel clamped and clipped the bottom of the list.
        .frame(maxHeight: Theme.expandedContentMaxHeight)
    }

    private var filteredGroups: [(cwd: String, agents: [ClaudeAgentSummary])] {
        guard !searchText.isEmpty else { return controller.overviewMonitor.projectGroups }
        return controller.overviewMonitor.projectGroups.filter {
            $0.cwd.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var header: some View {
        HStack {
            Text("Claude Code")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Button(showingNewAgentForm ? "Cancel" : "+ New Agent") {
                withAnimation(.snappy(duration: 0.2)) { showingNewAgentForm.toggle() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.inactiveTabBackground))
        }
        .padding(.horizontal, 20)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 20)
    }

    private var newAgentForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Project path (e.g. ~/code/my-project)", text: $newAgentProjectPath)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(8)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous))
            TextField("What should it do?", text: $newAgentPrompt)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(8)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous))
            Button("Start") {
                let path = (newAgentProjectPath as NSString).expandingTildeInPath
                guard !path.isEmpty, !newAgentPrompt.isEmpty else { return }
                controller.startAgent(projectPath: path, firstMessage: newAgentPrompt)
                newAgentProjectPath = ""
                newAgentPrompt = ""
                showingNewAgentForm = false
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.inactiveTabBackground))
        }
        .padding(.horizontal, 20)
    }
}

private struct ClaudeProjectGroupCard: View {
    let group: (cwd: String, agents: [ClaudeAgentSummary])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((group.cwd as NSString).lastPathComponent)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.primaryText)

            ForEach(group.agents) { agent in
                HStack(spacing: 8) {
                    Circle()
                        .fill(agent.isBackground ? Theme.amber : Theme.secondaryText)
                        .frame(width: 6, height: 6)
                    Text(agent.name ?? String(agent.sessionId.prefix(8)))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.primaryText.opacity(0.85))
                        .lineLimit(1)
                    Spacer()
                    Text(agent.displayStatus)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                    Text(agent.isBackground ? "Background" : "Interactive")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }
}

private struct ClaudeOwnedAgentCard: View {
    let controller: ClaudeSessionsController
    let agent: ClaudeOwnedAgent
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(agent.projectName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text(stateLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                Button("Stop") { controller.stopAgent(agent) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.danger)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(agent.turns) { turn in
                        Text(turn.text)
                            .font(.system(size: 11, design: turn.role == .tool ? .monospaced : .default))
                            .foregroundStyle(turn.role == .user ? Theme.primaryText : Theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 90)

            if let pending = agent.pendingPermission {
                HStack(spacing: 8) {
                    Text("Allow \(pending.toolName)?")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Button("Decline") { controller.respondToPermission(agent, allow: false) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                    Button("Accept") { controller.respondToPermission(agent, allow: true) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                }
                .padding(8)
                .background(Theme.rowHover, in: RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous))
            } else {
                HStack(spacing: 8) {
                    TextField("Message", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .onSubmit(sendDraft)
                    Button("Send", action: sendDraft)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .disabled(draft.isEmpty)
                }
            }
        }
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }

    private var stateLabel: String {
        switch agent.state {
        case .starting: "Starting…"
        case .running: "Running…"
        case .waitingForInput: "Waiting"
        case .exited: "Exited"
        case .failed(let message): "Error: \(message)"
        }
    }

    private func sendDraft() {
        guard !draft.isEmpty else { return }
        controller.send(draft, to: agent)
        draft = ""
    }
}
