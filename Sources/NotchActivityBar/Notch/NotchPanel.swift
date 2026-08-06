import AppKit

final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        // Take key status only when a view actually asks for it (e.g. clicking
        // into a text field), so hovering/buttons never steal focus from the
        // frontmost app. Combined with .nonactivatingPanel, typing works
        // without activating this app.
        becomesKeyOnlyIfNeeded = true

        // The window frame is transparent padding around a much smaller visible
        // shape. Without this, the full rectangular frame is mouse-hit-testable
        // at the same window level as the system menu bar, which silently
        // swallows clicks meant for Control Center / other menu bar items even
        // when nothing is visibly drawn there. NotchPanelController toggles this
        // back to `false` only while the cursor is actually over the drawn
        // pill/panel, so the window is click-through everywhere else.
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
