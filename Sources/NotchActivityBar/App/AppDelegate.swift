import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = NotchPanelController()
        panelController = controller
        controller.start()

        statusItemController = StatusItemController(panelController: controller)

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
