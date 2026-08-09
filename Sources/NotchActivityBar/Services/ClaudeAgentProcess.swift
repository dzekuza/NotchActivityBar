import Foundation

/// Owns one `claude -p --input-format stream-json --output-format
/// stream-json` subprocess: a headless session that stays alive reading
/// newline-delimited JSON user turns from stdin and emitting
/// newline-delimited JSON events on stdout, so a single process supports a
/// full multi-turn conversation (verified against a real `claude` binary).
@MainActor
final class ClaudeAgentProcess {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private var stdoutBuffer = Data()
    private(set) var isRunning = false

    var onEvent: ((ClaudeStreamEvent) -> Void)?
    var onExit: ((Int32) -> Void)?

    func start(claudePath: String, projectPath: String, settingsPath: String) throws {
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--settings", settingsPath,
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.handleStdout(data) }
        }

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self else { return }
                self.isRunning = false
                self.onExit?(proc.terminationStatus)
            }
        }

        try process.run()
        isRunning = true
    }

    func send(userText: String) {
        guard isRunning else { return }
        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [["type": "text", "text": userText]],
            ],
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        data.append(0x0A)
        try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }

    func terminate() {
        guard isRunning else { return }
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe.fileHandleForWriting.close()
        process.terminate()
        isRunning = false
    }

    private func handleStdout(_ data: Data) {
        stdoutBuffer.append(data)
        while let newlineRange = stdoutBuffer.range(of: Data([0x0A])) {
            let lineData = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<newlineRange.lowerBound)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex..<newlineRange.upperBound)
            guard !lineData.isEmpty, let event = ClaudeStreamEventParser.parse(lineData) else { continue }
            onEvent?(event)
        }
    }
}
