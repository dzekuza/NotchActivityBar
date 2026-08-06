import AppKit
import SwiftUI

struct SettingsTabView: View {
    let apiKeyStore: GeminiAPIKeyStore

    @State private var keyInput = ""
    @State private var showSavedConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Gemini API Key")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("Used to transcribe meetings and calls via Gemini Live. Stored securely in the Keychain.")
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
        return apiKeyStore.hasKey ? "A key is configured" : "No key configured — transcription is disabled"
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
