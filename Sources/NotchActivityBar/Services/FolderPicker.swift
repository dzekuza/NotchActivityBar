import AppKit

/// Directory chooser for the notch panel.
///
/// Two things have to be arranged before `NSOpenPanel` behaves here. The app is
/// a windowless `.accessory` agent that is never key, so it needs the same
/// brief promotion to `.regular` that TCC alerts need (see `PermissionPrompt`)
/// — otherwise the picker can open behind everything or not at all. And the
/// expanded notch panel collapses on mouse-out, so it has to be pinned for the
/// duration or the form disappears the moment the cursor reaches the picker.
@MainActor
enum FolderPicker {
    static func chooseDirectory(startingAt path: String?) -> String? {
        NotchPanelHold.acquire()
        PermissionPrompt.activate()
        defer {
            PermissionPrompt.restore()
            NotchPanelHold.release()
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the project folder for this agent"
        // The notch panels live at `.statusBar`, which outranks the level a
        // modal open panel gets by default — without this the picker opens
        // *underneath* the notch it was launched from.
        panel.level = .popUpMenu

        let start = path.map { ($0 as NSString).expandingTildeInPath } ?? ""
        var isDirectory: ObjCBool = false
        if !start.isEmpty, FileManager.default.fileExists(atPath: start, isDirectory: &isDirectory), isDirectory.boolValue {
            panel.directoryURL = URL(fileURLWithPath: start)
        } else {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        }

        guard panel.runModal() == .OK else { return nil }
        return panel.url?.path
    }
}
