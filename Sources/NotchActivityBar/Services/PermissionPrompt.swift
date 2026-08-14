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
///
/// Multiple permission flows (speech, mic, camera, screenshot-folder warm-up)
/// can be triggered concurrently — e.g. a meeting auto-starting at launch
/// fires speech + mic requests in the same tick as the screenshot monitor's
/// folder warm-up. `activate`/`restore` reference-counts these overlapping
/// requests so an early `restore()` from one flow doesn't demote the app
/// back to `.accessory` while a sibling request's TCC alert is still meant
/// to be frontmost.
@MainActor
enum PermissionPrompt {
    private static var activeRequests = 0

    static func activate() {
        activeRequests += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func restore() {
        activeRequests = max(0, activeRequests - 1)
        guard activeRequests == 0 else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    static func around<T>(_ request: () async -> T) async -> T {
        activate()
        let result = await request()
        restore()
        return result
    }
}
