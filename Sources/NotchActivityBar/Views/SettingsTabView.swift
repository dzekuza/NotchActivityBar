import AppKit
import CoreAudio
import SwiftUI

struct SettingsTabView: View {
    @State private var deviceManager = AudioDeviceManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Microphone Input Device")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("Select which microphone input to use for call and meeting audio capture.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)

                HStack(spacing: 10) {
                    Picker("", selection: Binding(
                        get: { deviceManager.selectedDeviceID ?? 0 },
                        set: { newID in deviceManager.selectedDeviceID = (newID == 0 ? nil : newID) }
                    )) {
                        Text("System Default Input").tag(AudioDeviceID(0))
                        ForEach(deviceManager.availableDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    Button {
                        deviceManager.refreshDevices()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh connected audio input devices")
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Meeting Transcription")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("Calls and meetings are transcribed on-device using Apple's Speech framework. No account or API key needed — the first recording will prompt for Speech Recognition access.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(width: Theme.expandedWidth, alignment: .leading)
    }
}
