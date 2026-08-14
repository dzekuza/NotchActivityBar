import AppKit
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController?
    private var statusItemController: StatusItemController?
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = NotchPanelController(onCheckForUpdates: { [weak self] in
            self?.updaterController.checkForUpdates(nil)
        })
        panelController = controller
        controller.start()

        statusItemController = StatusItemController(panelController: controller, updaterController: updaterController)

        DispatchQueue.main.async {
            NSApp.windows
                .filter { !($0 is NotchPanel) }
                .forEach { $0.close() }
        }
    }

    /// Persist any in-progress meeting transcript instead of discarding it, and
    /// wait for the write to actually land before the process exits — a
    /// fire-and-forget `Task` from a plain `applicationWillTerminate` could be
    /// killed mid-write once this method returns and macOS proceeds to quit.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let panelController else { return .terminateNow }

        Task { @MainActor in
            await panelController.meetingRecorderController.stopAndWaitForPersistence()
            panelController.privacyGuardController.setMuted(false)
            panelController.claudeSessionsController.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
