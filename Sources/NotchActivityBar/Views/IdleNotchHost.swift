import AppKit
import SwiftUI

struct IdleNotchHost: View {
    var size: CGSize = CGSize(width: Theme.idleWidth, height: Theme.idleHeight)
    var cornerRadius: CGFloat = 14
    var toast: NotchToast?
    var isRecording: Bool = false
    var liveTranscript: String = ""
    var onStopRecording: () -> Void = {}

    @State private var launchAtLogin = false

    var body: some View {
        IdleNotchView(
            size: size,
            cornerRadius: cornerRadius,
            toast: toast,
            isRecording: isRecording,
            liveTranscript: liveTranscript,
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
    }
}
