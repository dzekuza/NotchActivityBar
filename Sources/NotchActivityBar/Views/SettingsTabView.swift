import AppKit
import CoreAudio
import SwiftUI

struct SettingsTabView: View {
    let aiSettings: MeetingAISettings
    let apiKeyStore: GeminiAPIKeyStore
    let permissions: PermissionsController
    let onCheckForUpdates: () -> Void

    @State private var deviceManager = AudioDeviceManager.shared
    @State private var keyInput = ""
    @State private var showSavedConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Grouped, not loose: this VStack is already at `ViewBuilder`'s
            // ten-child ceiling, so the permissions section and its divider have
            // to count as one. Unwrapping them breaks the build.
            Group {
                permissionsSection
                Divider()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Microphone Input Device")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("Select which microphone input to use for call and meeting audio capture.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)

                HStack(spacing: 8) {
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
                    .controlSize(.small)

                    Button {
                        deviceManager.refreshDevices()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh connected audio input devices")
                    .accessibilityLabel("Refresh connected audio input devices")
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Text("Meeting Transcription")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("Apple Speech transcribes fully on-device with no key needed, but doesn't support every language. Gemini Live covers more languages (e.g. Lithuanian) and also enables AI meeting summaries — both need an API key below.")
                    .font(.system(size: 11))
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
                .controlSize(.small)

                if aiSettings.engine == .geminiLive {
                    HStack(spacing: 6) {
                        Text("Language")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                        TextField("Auto-detect (e.g. lt-LT for Lithuanian)", text: Binding(
                            get: { aiSettings.languageCode },
                            set: { aiSettings.languageCode = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.primaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                                .fill(Theme.cardBackground)
                        )
                        .frame(maxWidth: 240)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(
                    get: { aiSettings.isSummaryEnabled },
                    set: { aiSettings.isSummaryEnabled = $0 }
                )) {
                    Text("Generate AI summary after each meeting")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Text("Uses the Gemini API key below. Requires network access after recording stops.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gemini API Key")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text("Used for Gemini Live transcription and AI meeting summaries. Stored securely in the Keychain.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }

                HStack(spacing: 8) {
                    SecureField("AIza...", text: $keyInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                                .fill(Theme.cardBackground)
                        )
                        .frame(maxWidth: 320)
                        .onSubmit(saveKey)

                    Button(action: saveKey) {
                        Text("Save")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.activeTabText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Theme.activeTabBackground))
                    }
                    .buttonStyle(.plain)
                    .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if apiKeyStore.hasKey {
                        Button(action: clearKey) {
                            Text("Remove")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.danger)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Theme.danger.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(statusColor)
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(statusColor)

                    Spacer(minLength: 12)

                    Button {
                        if let url = URL(string: "https://aistudio.google.com/apikey") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("Get a key at aistudio.google.com")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Text("Software Update")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)

                Button(action: onCheckForUpdates) {
                    Text("Check for Updates…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.inactiveTabBackground))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .frame(width: Theme.expandedWidth, alignment: .leading)
        // macOS has no notification for a TCC change, so the app would otherwise
        // keep displaying whatever it happened to read at launch. Re-reading
        // every time this tab appears (on top of `PermissionsController`'s
        // app-activation hook) makes "I just changed it in System Settings"
        // show up here instead of looking cached.
        .onAppear { permissions.refresh() }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Recording Permissions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)

                Spacer()

                Button {
                    permissions.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Re-check permissions")
                .accessibilityLabel("Re-check recording permissions")
            }

            Text("Recording a meeting needs all three. macOS doesn't notify apps when you change these, so re-check after editing them in System Settings.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)

            ForEach(PermissionsController.Kind.allCases) { kind in
                permissionRow(kind)
            }

            if permissions.screenRecordingNeedsRelaunch {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.amber)
                    Text("Screen Recording was granted after launch — macOS only applies it to a freshly started app.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.amber)

                    Spacer(minLength: 8)

                    Button(action: relaunch) {
                        Text("Relaunch")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.activeTabText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Theme.activeTabBackground))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func permissionRow(_ kind: PermissionsController.Kind) -> some View {
        let status = permissions.status(for: kind)
        return HStack(spacing: 8) {
            Image(systemName: status.isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(status.isGranted ? Color.green : Theme.amber)

            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                Text(kind.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer(minLength: 12)

            if status.isGranted {
                Text("Allowed")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Button {
                    permissions.request(kind)
                } label: {
                    Text(status == .notDetermined ? "Allow…" : "Open Settings…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.inactiveTabBackground))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Grant \(kind.title) access")
            }
        }
        .padding(.vertical, 2)
    }

    /// Screen Recording grants only reach a process that was launched after the
    /// switch was flipped, so offer the same escape hatch macOS's own alert does.
    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            // `any Error` isn't Sendable, so pull the message out here rather
            // than carrying the error itself across to the main actor.
            let failure = error?.localizedDescription
            Task { @MainActor in
                if let failure {
                    NSLog("SettingsTabView: relaunch failed — \(failure)")
                    return
                }
                NSApp.terminate(nil)
            }
        }
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
