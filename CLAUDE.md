# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS menu-bar/notch utility app (SwiftPM executable, macOS 14+, Swift 6 language mode, strict concurrency). It renders a custom borderless panel docked at the screen's notch/menu-bar area that expands on hover to show clipboard history, screenshot history, meeting recordings/transcripts, and notes. Auto-updates via Sparkle.

## Build & run

```bash
swift build                       # debug build
swift build -c release            # release build
swift run                         # run from source (Info.plist is linker-embedded, see Package.swift)
```

There is no test target in this package — no `swift test` suite exists.

### Packaging script: `Scripts/build_app.sh`

This is the only supported way to produce a runnable `.app` bundle (code signing, Sparkle framework embedding, and Info.plist require the bundle structure — `swift run` alone won't have a working bundle identifier for things like App Intents).

```bash
Scripts/build_app.sh                          # assemble dist/NotchActivityBar.app (dev-signed)
Scripts/build_app.sh --install                # build, install to /Applications, launch it
Scripts/build_app.sh --release --bump 1.2.3    # full release: sign w/ Developer ID, notarize, staple,
                                                # build DMG, regenerate appcast.xml, commit, tag, push,
                                                # and create a GitHub release (gh release create)
Scripts/build_app.sh --release --bump 1.2.3 --notes "..."   # custom release notes
```

Key details:
- `--bump` refuses to run if the working tree has uncommitted changes outside `Resources/Info.plist`/`appcast.xml`, and refuses if the version tag already exists locally or on origin.
- Dev builds sign with a Developer ID-backed "Apple Development" identity (stable across rebuilds — ad-hoc signing broke status-item scene registration between builds). Release builds use the "Developer ID Application" identity and must NOT carry the `get-task-allow` debug entitlement (Apple's notary service rejects it).
- Release builds require `Scripts/fetch_sparkle_tools.sh` to have fetched `Scripts/sparkle-tools/generate_appcast`, and a `notarytool` keychain profile named `notch-activity-bar-notary`.
- GitHub repo for releases: `dzekuza/NotchActivityBar`.

## Architecture

### Entry point & lifecycle

`NotchActivityBarApp` (SwiftUI `App`, empty `Settings` scene only — there's no real window) delegates everything to `AppDelegate`, which sets `.accessory` activation policy (no Dock icon), owns the Sparkle `SPUStandardUpdaterController`, and constructs a single `NotchPanelController` plus `StatusItemController` (the menu-bar icon and its menu: toggle bar, launch at login, check for updates, quit).

### The two-panel notch UI (`Notch/`)

`NotchPanelController` is the central coordinator. It owns two borderless, non-activating `NSPanel`s (`NotchPanel`, `.statusBar` level, `canJoinAllSpaces`):
- **idlePanel** — the small pill docked at the notch, always visible when enabled. Hosts `IdleNotchHost`/`IdleNotchView` via `NSHostingView`.
- **expandedPanel** — the full tabbed panel (`ExpandedPanelHost` → `ExpandedPanelView`), shown on hover.

Both panels default to `ignoresMouseEvents = true` so they never swallow clicks meant for the real menu bar/Control Center. `NotchPanelController` runs a single global+local `NSEvent` mouse-moved monitor as the *sole* source of truth for both click-through gating and expand/collapse — this is deliberate (see the long comment above `startMouseMonitor()`): relying on SwiftUI `onHover` here caused a visible expand/collapse/expand flicker on first hover, because a click-through panel never receives AppKit hover events until this monitor has already re-enabled them.

`NotchGeometry.resolve(for:)` detects whether the display has a physical camera notch (via `safeAreaInsets.top` + `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`) and sizes/positions the idle panel accordingly, falling back to a fixed pill for notch-less displays.

Panel resize/reposition is frame-based (`NSAnimationContext` + `.animator()`), not SwiftUI-driven — `ExpandedPanelView` reports its content height up through an `onHeightChange` closure, and the controller clamps/animates the panel frame itself. The first resize after opening is snapped (not animated) to avoid a visible "closes then reopens" artifact, since the true content height only arrives a beat after the panel is shown at a guessed size.

### Feature domains

Each tab in `AppTab` (Clipboard, Meetings, Notes, Screenshots, Settings) is backed by an `@Observable @MainActor` controller/monitor in `Services/`, constructed once in `NotchPanelController.init()` and threaded down through `ExpandedPanelHost` → `ExpandedPanelView` → the tab-specific view:

- **Clipboard** — `ClipboardMonitor` polls the pasteboard; `NotchPanelController` shows a toast (`showToast(.clipboardCopied)`) on new items.
- **Screenshots** — `ScreenshotMonitor` watches for new screenshot files; same toast pattern.
- **Meetings** — `MeetingRecorderController` is the orchestrator: `CallActivityDetector` polls whether the system default input device is "running somewhere" (best-effort mic-in-use signal, CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere` — this is a heuristic, not per-app, so it can false-positive on any mic use) and auto-starts/stops recording. Recording itself is `MeetingAudioCapture` (ScreenCaptureKit-based) feeding PCM chunks to `AppleSpeechTranscriber` (on-device `Speech` framework) for a live transcript; sessions persist via `MeetingSessionStore`. `onRecordingStateChange` drives the notch's recording banner independent of SwiftUI observation.
- **Notes** — `NotesController` + `NotesStore`, simple CRUD with disk persistence.
- **Privacy Guard** — `PrivacyGuardController` mutes the default mic input and takes exclusive ownership (via CoreMediaIO) of every known camera device when engaged, so no other process can read from them. Camera hogging requires TCC camera authorization and silently no-ops until granted (first call triggers the OS prompt).

### Persistence

Simple `*Store` types (`MeetingSessionStore`, `NotesStore`) handle disk read/write for their respective models — no database, no CloudKit.

### Theming & layout constants

`Theme.swift` centralizes all colors, corner radii, panel dimensions (idle/expanded width & height, card sizes), and animation durations — check here before hardcoding a visual constant in a view.

## Signing identities & release credentials

Identity names/notary profile are hardcoded at the top of `Scripts/build_app.sh` and are specific to this developer's Apple account — do not assume they exist in other environments.
