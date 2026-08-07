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

        let controller = NotchPanelController()
        panelController = controller
        controller.start()

        statusItemController = StatusItemController(panelController: controller, updaterController: updaterController)

        DispatchQueue.main.async {
            NSApp.windows
                .filter { !($0 is NotchPanel) }
                .forEach { $0.close() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.privacyGuardController.setMuted(false)
    }
}
