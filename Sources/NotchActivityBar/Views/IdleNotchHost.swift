import AppKit
import SwiftUI

struct IdleNotchHost: View {
    var size: CGSize = CGSize(width: Theme.idleWidth, height: Theme.idleHeight)
    var cornerRadius: CGFloat = 14
    let onHoverChange: (Bool) -> Void

    @State private var launchAtLogin = false

    var body: some View {
        IdleNotchView(size: size, cornerRadius: cornerRadius)
            .onHover(perform: onHoverChange)
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
