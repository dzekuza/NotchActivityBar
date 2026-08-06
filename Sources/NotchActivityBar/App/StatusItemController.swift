import AppKit

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let panelController: NotchPanelController
    private let toggleItem: NSMenuItem
    private let loginItem: NSMenuItem
    private let menu: NSMenu

    init(panelController: NotchPanelController) {
        self.panelController = panelController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Notch Activity Bar")
            image?.isTemplate = true
            button.image = image
        }

        toggleItem = NSMenuItem(title: "Show Notch Bar", action: nil, keyEquivalent: "")
        loginItem = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")

        let menu = NSMenu()
        self.menu = menu

        toggleItem.target = self
        toggleItem.action = #selector(toggleEnabled)
        toggleItem.state = panelController.isEnabled ? .on : .off
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        loginItem.target = self
        loginItem.action = #selector(toggleLaunchAtLogin)
        loginItem.state = LoginItemManager.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let apiKeyItem = NSMenuItem(title: "Set Gemini API Key…", action: #selector(setGeminiAPIKey), keyEquivalent: "")
        apiKeyItem.target = self
        menu.addItem(apiKeyItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Notch Activity Bar", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func setGeminiAPIKey() {
        let alert = NSAlert()
        alert.messageText = "Gemini API Key"
        alert.informativeText = "Used to transcribe meetings/calls via Gemini. Get a key from aistudio.google.com."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "AIza..."
        field.stringValue = panelController.geminiAPIKeyStore.apiKey ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        if alert.runModal() == .alertFirstButtonReturn {
            panelController.geminiAPIKeyStore.setKey(field.stringValue)
        }
    }

    @objc private func toggleEnabled() {
        let newValue = !panelController.isEnabled
        panelController.setEnabled(newValue)
        toggleItem.state = newValue ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        let newValue = !LoginItemManager.isEnabled
        LoginItemManager.setEnabled(newValue)
        loginItem.state = newValue ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
