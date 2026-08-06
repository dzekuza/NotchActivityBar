import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class NotchPanelController {
    let clipboardMonitor = ClipboardMonitor()
    let screenshotMonitor = ScreenshotMonitor()
    let privacyGuardController = PrivacyGuardController()
    lazy var meetingRecorderController = MeetingRecorderController()

    private let idlePanel: NotchPanel
    private let expandedPanel: NotchPanel
    private var collapseTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var idleHostingView: NSHostingView<IdleNotchHost>?
    private nonisolated(unsafe) var globalMouseMonitor: Any?
    private nonisolated(unsafe) var localMouseMonitor: Any?
    private var isClickThroughDisabled = false

    private var idleGeometry = NotchGeometry(width: Theme.idleWidth, height: Theme.idleHeight, hasPhysicalNotch: false)
    private var idleCornerRadius: CGFloat = 14
    private var currentToast: NotchToast?
    private var isRecordingBannerActive = false
    private(set) var isEnabled = false
    private var lastExpandedHeight: CGFloat = Theme.idleHeight
    private var suppressNextExpandedResizeAnimation = false

    init() {
        idlePanel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: Theme.idleWidth, height: Theme.idleHeight))
        expandedPanel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: Theme.expandedWidth, height: Theme.idleHeight))

        expandedPanel.contentView = NSHostingView(
            rootView: ExpandedPanelHost(
                clipboardMonitor: clipboardMonitor,
                screenshotMonitor: screenshotMonitor,
                privacyGuardController: privacyGuardController,
                meetingRecorderController: meetingRecorderController,
                onHoverChange: { [weak self] in self?.handleExpandedHover($0) },
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
        NotificationCenter.default.addObserver(
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
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled

        if enabled {
            clipboardMonitor.start()
            screenshotMonitor.start()
            meetingRecorderController.start()
            positionIdlePanel()
            idlePanel.orderFrontRegardless()
        } else {
            collapseTask?.cancel()
            toastTask?.cancel()
            currentToast = nil
            expandedPanel.orderOut(nil)
            idlePanel.orderOut(nil)
            clipboardMonitor.stop()
            screenshotMonitor.stop()
            meetingRecorderController.stop()
            privacyGuardController.setMuted(false)
            setClickThroughDisabled(false)
        }
    }

    // MARK: - Click-through gating
    //
    // The panels sit at `.statusBar` window level so they can render above the
    // real menu bar / full-screen apps. Their frames include transparent
    // padding around the visible pill/panel, and by default `ignoresMouseEvents`
    // is `true` (set in `NotchPanel.init`) so that padding never intercepts
    // clicks meant for Control Center or other menu bar items. This monitor
    // watches the global cursor position and flips `ignoresMouseEvents` to
    // `false` only while the cursor is within the currently visible panel's
    // frame, restoring normal hover/click behavior for the notch bar itself.
    private func startMouseMonitor() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.updateClickThrough() }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            handler(event)
            return event
        }
    }

    private func updateClickThrough() {
        guard isEnabled else { return }

        let location = NSEvent.mouseLocation
        let overIdle = idlePanel.isVisible && idlePanel.frame.contains(location)
        let overExpanded = expandedPanel.isVisible && expandedPanel.frame.contains(location)
        setClickThroughDisabled(overIdle || overExpanded)
    }

    private func setClickThroughDisabled(_ disabled: Bool) {
        guard disabled != isClickThroughDisabled else { return }
        isClickThroughDisabled = disabled
        idlePanel.ignoresMouseEvents = !disabled
        expandedPanel.ignoresMouseEvents = !disabled
    }

    private var mainScreen: NSScreen? { NSScreen.main }

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
        let extended = currentToast != nil || isRecordingBannerActive
        let height = idleGeometry.height + (extended ? Theme.toastExtraHeight : 0)
        applyIdlePanelState(width: idleGeometry.width, height: height, toast: currentToast, animated: animated)
    }

    private func applyIdlePanelState(width: CGFloat, height: CGFloat, toast: NotchToast?, animated: Bool) {
        guard let screen = mainScreen else { return }

        let host = IdleNotchHost(
            size: CGSize(width: width, height: height),
            cornerRadius: idleCornerRadius,
            toast: toast,
            isRecording: isRecordingBannerActive,
            liveTranscript: meetingRecorderController.activeTranscriber?.transcript ?? "",
            pillHeight: idleGeometry.height,
            onStopRecording: { [weak self] in self?.meetingRecorderController.toggleManually() },
            onHoverChange: { [weak self] in self?.handleIdleHover($0) }
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
                context.duration = 0.28
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
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                expandedPanel.animator().setFrame(frame, display: true)
            }
        } else {
            expandedPanel.setFrame(frame, display: true)
        }
    }

    private func handleIdleHover(_ hovering: Bool) {
        if hovering {
            collapseTask?.cancel()
            // Position at the last known size before showing so the panel never
            // flashes at its stale/default (0,0) frame while SwiftUI's height
            // callback catches up asynchronously.
            applyExpandedPanelFrame(height: lastExpandedHeight, animated: false)
            expandedPanel.orderFrontRegardless()
            suppressNextExpandedResizeAnimation = true
        } else {
            // Once the expanded panel is showing, it sits on top of and fully
            // covers the idle pill's hover region — AppKit delivers that as a
            // mouseExited on the (now-occluded) idle panel even though the
            // cursor never actually left the notch, which would otherwise
            // schedule a collapse the instant the expanded panel appears.
            // From here on, only the expanded panel's own hover (below) should
            // drive collapse.
            guard !expandedPanel.isVisible else { return }
            scheduleCollapse()
        }
    }

    private func handleExpandedHover(_ hovering: Bool) {
        if hovering {
            collapseTask?.cancel()
        } else {
            scheduleCollapse()
        }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            self?.expandedPanel.orderOut(nil)
        }
    }
}
