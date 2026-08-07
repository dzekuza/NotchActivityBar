import AppKit
import Sparkle

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let panelController: NotchPanelController
    private let updaterController: SPUStandardUpdaterController
    private let toggleItem: NSMenuItem
    private let loginItem: NSMenuItem
    private let menu: NSMenu

    init(panelController: NotchPanelController, updaterController: SPUStandardUpdaterController) {
        self.panelController = panelController
        self.updaterController = updaterController
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

        let checkForUpdatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        checkForUpdatesItem.target = self
        menu.addItem(checkForUpdatesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Notch Activity Bar", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
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

    @objc private func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
