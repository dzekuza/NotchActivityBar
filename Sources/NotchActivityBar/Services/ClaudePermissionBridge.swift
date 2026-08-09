import Foundation

/// Bridges an app-owned `claude` subprocess's `PreToolUse` hook back to this
/// app so a human can accept/decline each tool call from the notch UI.
///
/// Claude Code hooks run synchronously and block the CLI until the hook
/// process exits (confirmed against a real `claude` binary), so the bundled
/// hook script below simply dumps its stdin JSON to a per-request file and
/// polls for a one-word decision file this app writes in response, then
/// prints the required `hookSpecificOutput` JSON and exits.
@MainActor
final class ClaudePermissionBridge {
    let agentDir: URL
    private let requestsDir: URL
    private let responsesDir: URL
    private var timer: Timer?
    private var seenRequestIDs: Set<String> = []

    var onRequest: ((ClaudePermissionRequest) -> Void)?

    init(agentID: UUID) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchActivityBar/ClaudeAgents/\(agentID.uuidString)", isDirectory: true)
        agentDir = base
        requestsDir = base.appendingPathComponent("requests", isDirectory: true)
        responsesDir = base.appendingPathComponent("responses", isDirectory: true)
        try? FileManager.default.createDirectory(at: requestsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: responsesDir, withIntermediateDirectories: true)
    }

    /// Writes the hook script + a `--settings` JSON file wiring it into
    /// `PreToolUse`, and returns the settings file path to pass to `claude`.
    func writeSettingsFile() throws -> URL {
        let scriptURL = agentDir.appendingPathComponent("permission-hook.sh")
        try Self.hookScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let settings: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    [
                        "matcher": "*",
                        "hooks": [
                            ["type": "command", "command": scriptURL.path],
                        ],
                    ],
                ],
            ],
        ]
        let settingsURL = agentDir.appendingPathComponent("settings.json")
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted])
        try data.write(to: settingsURL)
        return settingsURL
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func respond(id: String, allow: Bool) {
        let word = allow ? "allow" : "deny"
        try? word.write(to: responsesDir.appendingPathComponent("\(id).decision"), atomically: true, encoding: .utf8)
    }

    func cleanUp() {
        stop()
        try? FileManager.default.removeItem(at: agentDir)
    }

    private func poll() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: requestsDir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            let id = file.deletingPathExtension().lastPathComponent
            guard !seenRequestIDs.contains(id) else { continue }
            seenRequestIDs.insert(id)

            guard let data = try? Data(contentsOf: file),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let toolName = obj["tool_name"] as? String
            else { continue }

            let inputSummary = (obj["tool_input"] as? [String: Any])
                .map { $0.map { "\($0.key): \($0.value)" }.joined(separator: ", ") } ?? ""
            onRequest?(ClaudePermissionRequest(id: id, toolName: toolName, inputSummary: inputSummary))
        }
    }

    /// Correlates requests/responses by a freshly generated id (not Claude's
    /// `tool_use_id`) so the script never needs to parse JSON itself — it
    /// just pipes stdin through verbatim and reads back a plain decision word.
    private static let hookScript = """
    #!/bin/bash
    dir="$(cd "$(dirname "$0")" && pwd)"
    id="$(uuidgen)"
    cat > "$dir/requests/$id.json"
    response_file="$dir/responses/$id.decision"
    for i in $(seq 1 1200); do
      if [ -f "$response_file" ]; then
        decision="$(cat "$response_file")"
        rm -f "$response_file"
        if [ "$decision" = "allow" ]; then
          echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
        else
          echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Declined in NotchActivityBar"}}'
        fi
        exit 0
      fi
      sleep 0.5
    done
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"NotchActivityBar: request timed out"}}'
    exit 0
    """
}
