import AppKit

enum ScreenRecordingLauncher {
    /// Opens the built-in Screenshot app, which shows the same capture/record
    /// toolbar as ⌘⇧5 with screen recording options.
    private static let candidatePaths = [
        "/System/Applications/Utilities/Screenshot.app",
        "/System/Library/CoreServices/Applications/Screenshot.app",
    ]

    static func openScreenRecordingControls() {
        guard let screenshotAppURL = candidatePaths
            .map(URL.init(fileURLWithPath:))
            .first(where: { FileManager.default.fileExists(atPath: $0.path) })
        else {
            NSLog("ScreenRecordingLauncher: could not locate Screenshot.app")
            return
        }

        NSWorkspace.shared.openApplication(at: screenshotAppURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                NSLog("ScreenRecordingLauncher: failed to open Screenshot.app — \(error.localizedDescription)")
            }
        }
    }
}
