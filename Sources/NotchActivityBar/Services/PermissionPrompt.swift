import AppKit

/// `NotchActivityBar` runs as a menu-bar-only `.accessory` app with no
/// regular window, which means it's never "key" — and a background agent
/// with no key window frequently can't get the system to surface a TCC
/// consent alert at all. Instead of prompting, the request silently
/// resolves to denied/unauthorized and no decision is ever recorded, so the
/// user never even sees the dialog to grant it.
///
/// Briefly promoting to `.regular` and activating around the request call
/// gives the OS a real frontmost app to attach the alert to, which reliably
/// surfaces it. Callers activate before issuing the request and restore
/// right after the result (sync return or async callback) arrives.
@MainActor
enum PermissionPrompt {
    static func activate() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func restore() {
        NSApp.setActivationPolicy(.accessory)
    }

    static func around<T>(_ request: () async -> T) async -> T {
        activate()
        let result = await request()
        restore()
        return result
    }
}
