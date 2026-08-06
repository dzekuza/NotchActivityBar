import SwiftUI

struct SearchBarView: View {
    @Binding var text: String
    let onClearAll: () -> Void
    var isPrivacyMuted: Bool = false
    var cameraAccessDenied: Bool = false
    var isRecording: Bool = false
    var onToggleRecording: () -> Void = {}
    var onTogglePrivacyMute: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
                TextField("Search...", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primaryText)
            }

            Spacer(minLength: 12)

            iconButton(
                systemImage: "record.circle",
                tint: Theme.danger,
                isActive: isRecording,
                help: isRecording ? "Stop Recording" : "Start Live Recording",
                action: onToggleRecording
            )

            iconButton(
                systemImage: isPrivacyMuted ? "video.slash.fill" : "video.fill",
                tint: Theme.danger,
                isActive: isPrivacyMuted,
                help: cameraAccessDenied
                    ? "Camera access denied — enable it in System Settings > Privacy & Security > Camera"
                    : (isPrivacyMuted ? "Unmute Microphone & Camera" : "Mute Microphone & Camera"),
                action: onTogglePrivacyMute
            )
            .overlay(alignment: .topTrailing) {
                if cameraAccessDenied {
                    Circle()
                        .fill(Theme.danger)
                        .frame(width: 7, height: 7)
                        .offset(x: 2, y: -2)
                }
            }

            Button(action: onClearAll) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.inactiveTabBackground))
            }
            .buttonStyle(.plain)

            iconButton(
                systemImage: "power",
                tint: Theme.danger,
                isActive: false,
                help: "Quit Notch Activity Bar",
                action: { NSApp.terminate(nil) }
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private func iconButton(systemImage: String, tint: Color, isActive: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? tint : Theme.tertiaryText)
                .frame(width: 30, height: 30)
                .background(Circle().fill(isActive ? tint.opacity(0.18) : Theme.inactiveTabBackground))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
