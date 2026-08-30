import Foundation

/// Pins the expanded notch panel open across a modal interaction.
///
/// The panel collapses as soon as the cursor leaves it (`NotchPanelController`'s
/// mouse monitor is the sole source of truth for that). Opening an `NSOpenPanel`
/// moves the cursor away immediately, so without a hold the notch would fold up
/// behind the picker and the half-filled form would vanish from under the user.
///
/// Reference-counted for the same reason as `PermissionPrompt`: overlapping
/// holds must not let the first release drop the pin while another modal is
/// still up.
@MainActor
enum NotchPanelHold {
    private static var holdCount = 0

    /// Set by `NotchPanelController` so it can re-evaluate hover state once the
    /// last hold goes away — by then the cursor has usually moved off the panel
    /// without the monitor being allowed to act on it.
    static var onRelease: (() -> Void)?

    static var isHeld: Bool { holdCount > 0 }

    static func acquire() {
        holdCount += 1
    }

    static func release() {
        holdCount = max(0, holdCount - 1)
        guard holdCount == 0 else { return }
        onRelease?()
    }
}
