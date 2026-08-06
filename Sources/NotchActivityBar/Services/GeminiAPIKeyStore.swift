import Foundation
import Observation

@MainActor
@Observable
final class GeminiAPIKeyStore {
    private static let service = "com.rysardgvozdovic.NotchActivityBar.gemini"
    private static let account = "api-key"

    private(set) var apiKey: String?

    init() {
        apiKey = KeychainStore.get(service: Self.service, account: Self.account)
    }

    var hasKey: Bool { apiKey != nil && !(apiKey?.isEmpty ?? true) }

    func setKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.set(trimmed, service: Self.service, account: Self.account)
        apiKey = trimmed
    }

    func clearKey() {
        KeychainStore.delete(service: Self.service, account: Self.account)
        apiKey = nil
    }
}
