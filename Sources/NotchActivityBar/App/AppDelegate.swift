import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = NotchPanelController()
        panelController = controller
        controller.start()

        DispatchQueue.main.async {
            NSApp.windows
                .filter { !($0 is NotchPanel) }
                .forEach { $0.close() }
        }
    }
}
