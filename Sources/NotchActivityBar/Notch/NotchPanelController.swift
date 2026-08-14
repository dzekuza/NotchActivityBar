import AppKit
import QuartzCore
import SwiftUI
import os

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchActivityBar", category: "Panel")

@MainActor
final class NotchPanelController {
    let clipboardMonitor = ClipboardMonitor()
    let screenshotMonitor = ScreenshotMonitor()
    let privacyGuardController = PrivacyGuardController()
    let notesController = NotesController()
    lazy var meetingRecorderController = MeetingRecorderController()
    let claudeSessionsController = ClaudeSessionsController()

    private let idlePanel: NotchPanel
    private let expandedPanel: NotchPanel
    private var collapseTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var idleHostingView: NSHostingView<IdleNotchHost>?
    private nonisolated(unsafe) var globalMouseMonitor: Any?
    private nonisolated(unsafe) var localMouseMonitor: Any?
    private nonisolated(unsafe) var screenParametersObserver: Any?
    private var isClickThroughDisabled = false
    private var isHoveringExpandRegion = false

    private var idleGeometry = NotchGeometry(width: Theme.idleWidth, height: Theme.idleHeight, hasPhysicalNotch: false)
    private var idleCornerRadius: CGFloat = 14
    private var currentToast: NotchToast?
    private var isRecordingBannerActive = false
    private(set) var isEnabled = false
    private var lastExpandedHeight: CGFloat = Theme.idleHeight
    private var suppressNextExpandedResizeAnimation = false

    private var reduceMotionEnabled: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(onCheckForUpdates: @escaping () -> Void) {
        idlePanel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: Theme.idleWidth, height: Theme.idleHeight))
        expandedPanel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: Theme.expandedWidth, height: Theme.idleHeight))

        expandedPanel.contentView = NSHostingView(
            rootView: ExpandedPanelHost(
                clipboardMonitor: clipboardMonitor,
                screenshotMonitor: screenshotMonitor,
                privacyGuardController: privacyGuardController,
                meetingRecorderController: meetingRecorderController,
                notesController: notesController,
                claudeSessionsController: claudeSessionsController,
                onCheckForUpdates: { [weak self] in
                    // The notch panels sit at `.statusBar` level (always on
                    // top, even above normal windows) so Sparkle's update
                    // window would otherwise render hidden behind them and
                    // the app-modal session it runs blocks all other event
                    // delivery — reading as a total freeze. Collapse the
                    // panel and bring the app forward first so Sparkle's UI
                    // can actually appear and receive input.
                    self?.dismissExpandedPanel()
                    NSApp.activate(ignoringOtherApps: true)
                    onCheckForUpdates()
                },
                onHeightChange: { [weak self] in self?.resizeExpandedPanel(to: $0) }
            )
        )

        positionIdlePanel()

        clipboardMonitor.onNewItem = { [weak self] _ in self?.showToast(.clipboardCopied) }
        screenshotMonitor.onNewItem = { [weak self] _ in self?.showToast(.screenshotSaved) }
        meetingRecorderController.onRecordingStateChange = { [weak self] recording in
            guard let self else { return }
            self.isRecordingBannerActive = recording
            self.refreshIdlePanel(animated: true)
        }
    }

    func start() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.positionIdlePanel() }
        }

        setEnabled(true)
        startMouseMonitor()
    }

    deinit {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let screenParametersObserver { NotificationCenter.default.removeObserver(screenParametersObserver) }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled

        if enabled {
            clipboardMonitor.start()
            screenshotMonitor.start()
            meetingRecorderController.start()
            positionIdlePanel()
            idlePanel.alphaValue = 0
            idlePanel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotionEnabled ? 0 : 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                idlePanel.animator().alphaValue = 1
            }
        } else {
            collapseTask?.cancel()
            toastTask?.cancel()
            currentToast = nil
            isHoveringExpandRegion = false
            expandedPanel.alphaValue = 1
            expandedPanel.orderOut(nil)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = reduceMotionEnabled ? 0 : 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                idlePanel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.idlePanel.orderOut(nil)
                    self.idlePanel.alphaValue = 1
                }
            })
            clipboardMonitor.stop()
            screenshotMonitor.stop()
            meetingRecorderController.stop()
            claudeSessionsController.stop()
            privacyGuardController.setMuted(false)
            setClickThroughDisabled(false)
        }
    }

    // MARK: - Hover & click-through gating
    //
    // The panels sit at `.statusBar` window level so they can render above the
    // real menu bar / full-screen apps, and by default `ignoresMouseEvents` is
    // `true` (set in `NotchPanel.init`) so they never intercept clicks meant
    // for Control Center or other menu bar items. Because a panel that ignores
    // mouse events never receives AppKit's mouseEntered/exited, SwiftUI's
    // `onHover` can't be the source of truth for expand/collapse — it would
    // only fire *after* this monitor has already re-enabled event delivery,
    // one polled frame late, which is what caused the notch to visibly
    // expand/collapse/expand on the first hover of a session. Instead this
    // single poll loop is the only place that decides both click-through and
    // expand/collapse, so there's exactly one source of truth per mouse move.
    private func startMouseMonitor() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.updateHoverState() }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            handler(event)
            return event
        }
    }

    private func updateHoverState() {
        guard isEnabled else { return }

        let location = NSEvent.mouseLocation
        let overIdle = idlePanel.isVisible && idlePanel.frame.contains(location)
        let overExpanded = expandedPanel.isVisible && expandedPanel.frame.contains(location)
        setClickThroughDisabled(overIdle || overExpanded)

        // Only the idle pill itself (not the extended toast/recording banner
        // beneath it) should trigger expansion — otherwise the expanded panel
        // would cover the banner's Stop button and swallow its clicks.
        let overIdlePill = idlePanel.isVisible && idlePillFrame.contains(location)
        let shouldExpand = overIdlePill || overExpanded
        guard shouldExpand != isHoveringExpandRegion else { return }
        isHoveringExpandRegion = shouldExpand

        if shouldExpand {
            collapseTask?.cancel()
            guard !expandedPanel.isVisible else { return }
            presentExpandedPanel()
        } else {
            scheduleCollapse()
        }
    }

    private func presentExpandedPanel() {
        // Position at the last known size before showing so the panel never
        // flashes at its stale/default (0,0) frame while SwiftUI's height
        // callback catches up asynchronously.
        applyExpandedPanelFrame(height: lastExpandedHeight, animated: false)
        expandedPanel.alphaValue = 0
        expandedPanel.orderFrontRegardless()
        suppressNextExpandedResizeAnimation = true
        log.info("Expanded panel opened, height: \(self.lastExpandedHeight)")

        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotionEnabled ? 0 : 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            expandedPanel.animator().alphaValue = 1
        }
    }

    private var idlePillFrame: NSRect {
        let frame = idlePanel.frame
        return NSRect(
            x: frame.origin.x,
            y: frame.maxY - idleGeometry.height,
            width: frame.width,
            height: idleGeometry.height
        )
    }

    private func setClickThroughDisabled(_ disabled: Bool) {
        guard disabled != isClickThroughDisabled else { return }
        isClickThroughDisabled = disabled
        idlePanel.ignoresMouseEvents = !disabled
        expandedPanel.ignoresMouseEvents = !disabled
    }

    /// `NSScreen.main` (the screen containing the key window) is ambiguous for
    /// this app: it runs as a windowless `.accessory` with only non-activating
    /// panels, so there's no key window to anchor it. Prefer the display with
    /// a physical notch — the only screen this UI actually makes sense on —
    /// and fall back to `.main`/the first screen for notch-less setups.
    private var mainScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func positionIdlePanel() {
        guard isEnabled, let screen = mainScreen else { return }
        let geometry = NotchGeometry.resolve(for: screen)
        idleGeometry = geometry
        idleCornerRadius = geometry.hasPhysicalNotch ? 14 : min(10, geometry.height / 2)
        refreshIdlePanel(animated: false)
    }

    /// Recomputes the idle panel height from the current accessory state:
    /// extended while a toast or the recording banner is showing.
    private func refreshIdlePanel(animated: Bool) {
        let extra: CGFloat
        if currentToast != nil {
            extra = Theme.toastGap + Theme.toastPillHeight
        } else if isRecordingBannerActive {
            extra = Theme.toastGap + Theme.recordingPillHeight
        } else {
            extra = 0
        }
        let height = idleGeometry.height + extra
        applyIdlePanelState(width: idleGeometry.width, height: height, toast: currentToast, animated: animated)
    }

    private func applyIdlePanelState(width: CGFloat, height: CGFloat, toast: NotchToast?, animated: Bool) {
        guard let screen = mainScreen else { return }

        let host = IdleNotchHost(
            size: CGSize(width: width, height: height),
            pillHeight: idleGeometry.height,
            cornerRadius: idleCornerRadius,
            toast: toast,
            isRecording: isRecordingBannerActive,
            liveTranscript: meetingRecorderController.activeTranscriber?.transcript ?? "",
            onStopRecording: { [weak self] in self?.meetingRecorderController.toggleManually() }
        )
        if let idleHostingView {
            idleHostingView.rootView = host
        } else {
            let hostingView = NSHostingView(rootView: host)
            idleHostingView = hostingView
            idlePanel.contentView = hostingView
        }

        let frame = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotionEnabled ? 0 : 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                idlePanel.animator().setFrame(frame, display: true)
            }
        } else {
            idlePanel.setFrame(frame, display: true)
        }
    }

    private func showToast(_ toast: NotchToast) {
        guard isEnabled, !expandedPanel.isVisible else { return }

        toastTask?.cancel()
        currentToast = toast
        refreshIdlePanel(animated: true)

        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Theme.toastDuration))
            guard !Task.isCancelled, let self else { return }
            self.currentToast = nil
            // Falls back to the recording banner height if a recording is live.
            self.refreshIdlePanel(animated: true)
        }
    }

    private func resizeExpandedPanel(to height: CGFloat) {
        let clampedHeight = min(max(height, Theme.idleHeight), Theme.expandedMaxHeight)
        lastExpandedHeight = clampedHeight
        // The frame shown on open is a guess (the last known height, which on
        // the very first hover of a session is just the tiny idle height).
        // SwiftUI reports the real content height a beat later — animating
        // that correction reads as the panel visibly closing and reopening.
        // Snap the first post-open resize instead; only later resizes (e.g.
        // switching tabs while already open) should animate.
        let shouldAnimate = expandedPanel.isVisible && !suppressNextExpandedResizeAnimation
        suppressNextExpandedResizeAnimation = false
        applyExpandedPanelFrame(height: clampedHeight, animated: shouldAnimate)
    }

    private func applyExpandedPanelFrame(height: CGFloat, animated: Bool) {
        guard let screen = mainScreen else { return }
        let frame = NSRect(
            x: screen.frame.midX - Theme.expandedWidth / 2,
            y: screen.frame.maxY - height,
            width: Theme.expandedWidth,
            height: height
        )
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotionEnabled ? 0 : 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                expandedPanel.animator().setFrame(frame, display: true)
            }
        } else {
            expandedPanel.setFrame(frame, display: true)
        }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            self?.dismissExpandedPanel()
        }
    }

    private func dismissExpandedPanel() {
        guard expandedPanel.isVisible else { return }
        log.info("Expanded panel closed.")
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotionEnabled ? 0 : 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            expandedPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.expandedPanel.orderOut(nil)
                self.expandedPanel.alphaValue = 1
            }
        })
    }
}
