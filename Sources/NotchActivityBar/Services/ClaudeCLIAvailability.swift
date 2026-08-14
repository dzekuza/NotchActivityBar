import Foundation

/// Locates the `claude` executable on this machine. Not actor-isolated —
/// callers should resolve it off the main thread (it shells out to `which`
/// as a fallback) and hop back to update UI state.
enum ClaudeCLIAvailability {
    static func resolvePath() -> String? {
        let candidates = [
            "~/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ].map { ($0 as NSString).expandingTildeInPath }

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "claude"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty,
              FileManager.default.isExecutableFile(atPath: output)
        else { return nil }
        return output
    }
}
