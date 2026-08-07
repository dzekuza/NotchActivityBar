import AppKit
import CoreAudio
import SwiftUI

struct SettingsTabView: View {
    let aiSettings: MeetingAISettings
    let apiKeyStore: GeminiAPIKeyStore

    @State private var deviceManager = AudioDeviceManager.shared
    @State private var keyInput = ""
    @State private var showSavedConfirmation = false

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

            VStack(alignment: .leading, spacing: 8) {
                Text("Meeting Transcription")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("Apple Speech transcribes fully on-device with no key needed, but doesn't support every language. Gemini Live covers more languages (e.g. Lithuanian) and also enables AI meeting summaries — both need an API key below.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)

                Picker("", selection: Binding(
                    get: { aiSettings.engine },
                    set: { aiSettings.engine = $0 }
                )) {
                    ForEach(TranscriptionEngine.allCases) { engine in
                        Text(engine.label).tag(engine)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                if aiSettings.engine == .geminiLive {
                    HStack(spacing: 8) {
                        Text("Language")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                        TextField("Auto-detect (e.g. lt-LT for Lithuanian)", text: Binding(
                            get: { aiSettings.languageCode },
                            set: { aiSettings.languageCode = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                                .fill(Theme.cardBackground)
                        )
                        .frame(maxWidth: 260)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { aiSettings.isSummaryEnabled },
                    set: { aiSettings.isSummaryEnabled = $0 }
                )) {
                    Text("Generate AI summary after each meeting")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                }
                .toggleStyle(.switch)
                Text("Uses the Gemini API key below. Requires network access after recording stops.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Gemini API Key")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("Used for Gemini Live transcription and AI meeting summaries. Stored securely in the Keychain.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }

            HStack(spacing: 10) {
                SecureField("AIza...", text: $keyInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                            .fill(Theme.cardBackground)
                    )
                    .frame(maxWidth: 360)
                    .onSubmit(saveKey)

                Button(action: saveKey) {
                    Text("Save")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.activeTabText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.activeTabBackground))
                }
                .buttonStyle(.plain)
                .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if apiKeyStore.hasKey {
                    Button(action: clearKey) {
                        Text("Remove")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.danger)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Theme.danger.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(statusColor)

                Spacer(minLength: 12)

                Button {
                    if let url = URL(string: "https://aistudio.google.com/apikey") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("Get a key at aistudio.google.com")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(width: Theme.expandedWidth, alignment: .leading)
    }

    private var statusIcon: String {
        if showSavedConfirmation { return "checkmark.circle.fill" }
        return apiKeyStore.hasKey ? "checkmark.circle.fill" : "exclamationmark.circle"
    }

    private var statusColor: Color {
        if showSavedConfirmation { return .green }
        return apiKeyStore.hasKey ? Theme.secondaryText : Theme.amber
    }

    private var statusText: String {
        if showSavedConfirmation { return "Key saved" }
        return apiKeyStore.hasKey ? "A key is configured" : "No key configured — Gemini Live and AI summaries are disabled"
    }

    private func saveKey() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        apiKeyStore.setKey(trimmed)
        keyInput = ""
        showSavedConfirmation = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showSavedConfirmation = false
        }
    }

    private func clearKey() {
        apiKeyStore.clearKey()
        showSavedConfirmation = false
    }
}
