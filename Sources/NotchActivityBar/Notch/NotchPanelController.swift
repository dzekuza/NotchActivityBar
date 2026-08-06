import AppKit
import SwiftUI

@MainActor
final class NotchPanelController {
    let clipboardMonitor = ClipboardMonitor()
    let screenshotMonitor = ScreenshotMonitor()

    private let idlePanel: NotchPanel
    private let expandedPanel: NotchPanel
    private var collapseTask: Task<Void, Never>?
    private var idleHostingView: NSHostingView<IdleNotchHost>?

    init() {
        idlePanel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: Theme.idleWidth, height: Theme.idleHeight))
        expandedPanel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: Theme.expandedWidth, height: Theme.idleHeight))

        expandedPanel.contentView = NSHostingView(
            rootView: ExpandedPanelHost(
                clipboardMonitor: clipboardMonitor,
                screenshotMonitor: screenshotMonitor,
                onHoverChange: { [weak self] in self?.handleExpandedHover($0) },
                onHeightChange: { [weak self] in self?.resizeExpandedPanel(to: $0) }
            )
        )

        positionIdlePanel()
    }

    func start() {
        clipboardMonitor.start()
        screenshotMonitor.start()
        idlePanel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.positionIdlePanel() }
        }
    }

    private var mainScreen: NSScreen? { NSScreen.main }

    private func positionIdlePanel() {
        guard let screen = mainScreen else { return }
        let geometry = NotchGeometry.resolve(for: screen)
        let cornerRadius: CGFloat = geometry.hasPhysicalNotch ? 14 : min(10, geometry.height / 2)

        let host = IdleNotchHost(
            size: CGSize(width: geometry.width, height: geometry.height),
            cornerRadius: cornerRadius,
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
            x: screen.frame.midX - geometry.width / 2,
            y: screen.frame.maxY - geometry.height,
            width: geometry.width,
            height: geometry.height
        )
        idlePanel.setFrame(frame, display: true)
    }

    private func resizeExpandedPanel(to height: CGFloat) {
        guard let screen = mainScreen else { return }
        let clampedHeight = min(max(height, Theme.idleHeight), Theme.expandedMaxHeight)
        let frame = NSRect(
            x: screen.frame.midX - Theme.expandedWidth / 2,
            y: screen.frame.maxY - clampedHeight,
            width: Theme.expandedWidth,
            height: clampedHeight
        )
        expandedPanel.setFrame(frame, display: true)
    }

    private func handleIdleHover(_ hovering: Bool) {
        if hovering {
            collapseTask?.cancel()
            expandedPanel.orderFrontRegardless()
        } else {
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
