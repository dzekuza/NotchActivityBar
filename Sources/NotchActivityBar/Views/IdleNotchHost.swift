import AppKit
import SwiftUI

struct IdleNotchHost: View {
    var size: CGSize = CGSize(width: Theme.idleWidth, height: Theme.idleHeight)
    var notchWidth: CGFloat = Theme.idleWidth
    var pillHeight: CGFloat = Theme.idleHeight
    var cornerRadius: CGFloat = 14
    var toast: NotchToast?
    var isRecording: Bool = false
    var liveTranscript: String = ""
    var onStopRecording: () -> Void = {}
    var languagePrompt: LanguagePrompt?
    var onSelectLanguage: (String) -> Void = { _ in }
    var onConfirmLanguage: () -> Void = {}

    @State private var launchAtLogin = false

    var body: some View {
        IdleNotchView(
            size: size,
            notchWidth: notchWidth,
            pillHeight: pillHeight,
            cornerRadius: cornerRadius,
            toast: toast,
            isRecording: isRecording,
            liveTranscript: liveTranscript,
            onStopRecording: onStopRecording,
            languagePrompt: languagePrompt,
            onSelectLanguage: onSelectLanguage,
            onConfirmLanguage: onConfirmLanguage
        )
        .onAppear { launchAtLogin = LoginItemManager.isEnabled }
        .contextMenu {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    let actual = LoginItemManager.setEnabled(newValue)
                    if actual != newValue { launchAtLogin = actual }
                }
            Divider()
            Button("Quit Notch Activity Bar") {
                NSApp.terminate(nil)
            }
        }
    }
}
