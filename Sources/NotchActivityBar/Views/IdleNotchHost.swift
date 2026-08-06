import AppKit
import SwiftUI

struct IdleNotchHost: View {
    var size: CGSize = CGSize(width: Theme.idleWidth, height: Theme.idleHeight)
    var cornerRadius: CGFloat = 14
    var toast: NotchToast?
    var isRecording: Bool = false
    /// Height of the top pill region that triggers panel expansion on hover.
    /// While a banner (toast/recording) extends the panel downward, hovering
    /// the banner itself must NOT expand — the expanded panel would cover the
    /// Stop button and swallow its clicks.
    var pillHeight: CGFloat = Theme.idleHeight
    var onStopRecording: () -> Void = {}
    let onHoverChange: (Bool) -> Void

    @State private var launchAtLogin = false

    var body: some View {
        IdleNotchView(
            size: size,
            cornerRadius: cornerRadius,
            toast: toast,
            isRecording: isRecording,
            onStopRecording: onStopRecording
        )
        .onAppear { launchAtLogin = LoginItemManager.isEnabled }
        .contextMenu {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItemManager.setEnabled(newValue)
                }
            Divider()
            Button("Quit Notch Activity Bar") {
                NSApp.terminate(nil)
            }
        }
        .overlay(alignment: .top) {
            Color.clear
                .frame(width: size.width, height: min(pillHeight, size.height))
                .contentShape(Rectangle())
                .onHover(perform: onHoverChange)
        }
    }
}
