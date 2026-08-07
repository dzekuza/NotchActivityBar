import ServiceManagement

@MainActor
enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// - Returns: the resulting `isEnabled` state after the attempt, which may
    ///   not match `enabled` if registration/unregistration failed — callers
    ///   updating UI state (e.g. a menu checkmark) should use this, not the
    ///   requested value, so the UI never claims a state the system rejected.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("LoginItemManager: failed to update login item — \(error)")
        }
        return isEnabled
    }
}
