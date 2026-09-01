import Foundation
import Speech

/// A language a meeting can be transcribed in. `code` is a BCP-47 identifier,
/// or empty for "match the system".
struct MeetingLanguage: Identifiable, Equatable {
    let code: String
    let displayName: String

    var id: String { code }
}

/// What each engine can actually transcribe.
///
/// The two differ sharply, and pretending otherwise loses the recording: Apple
/// Speech ships a fixed set of 63 locales that notably excludes Lithuanian, so
/// picking it there silently yields an English-ish transcript. Gemini Live is
/// prompt-steered and takes anything. The picker offers each engine only what
/// it can honour.
enum MeetingLanguageCatalog {
    static let automatic = MeetingLanguage(code: "", displayName: "Auto (system language)")

    /// Offered for Gemini Live, which isn't restricted to a fixed list. Ordered
    /// by what this app's users are likely to be speaking rather than
    /// alphabetically.
    private static let geminiCodes = [
        "lt-LT", "en-US", "en-GB", "ru-RU", "pl-PL", "lv-LV", "et-EE", "uk-UA",
        "de-DE", "fr-FR", "es-ES", "it-IT", "pt-PT", "nl-NL", "sv-SE", "fi-FI",
        "da-DK", "nb-NO", "cs-CZ", "sk-SK", "hu-HU", "ro-RO", "tr-TR", "el-GR",
        "ja-JP", "ko-KR", "zh-CN", "ar-SA", "hi-IN",
    ]

    static func available(for engine: TranscriptionEngine) -> [MeetingLanguage] {
        switch engine {
        case .appleSpeech:
            let supported = SFSpeechRecognizer.supportedLocales()
                .map { MeetingLanguage(code: $0.identifier, displayName: displayName(for: $0.identifier)) }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            return [automatic] + supported
        case .geminiLive:
            return [automatic] + geminiCodes.map {
                MeetingLanguage(code: $0, displayName: displayName(for: $0))
            }
        }
    }

    static func displayName(for code: String) -> String {
        guard !code.isEmpty else { return automatic.displayName }
        let locale = Locale(identifier: code)
        return Locale.current.localizedString(forIdentifier: locale.identifier)
            ?? locale.identifier
    }

    /// Whether the engine can honour this language. Used to warn instead of
    /// letting a recording quietly come back in the wrong language.
    static func isSupported(_ code: String, by engine: TranscriptionEngine) -> Bool {
        guard !code.isEmpty else { return true }
        switch engine {
        case .appleSpeech: return resolvedAppleLocale(for: code) != nil
        case .geminiLive: return true
        }
    }

    /// Maps a requested code onto a locale `SFSpeechRecognizer` will actually
    /// accept, falling back to the same language in another region — the
    /// default system locale here is `en_LT`, which isn't in the supported set
    /// even though six English variants are.
    static func resolvedAppleLocale(for code: String) -> Locale? {
        let supported = SFSpeechRecognizer.supportedLocales()
        let normalized = code.replacingOccurrences(of: "_", with: "-")
        if let exact = supported.first(where: { $0.identifier.caseInsensitiveCompare(normalized) == .orderedSame }) {
            return exact
        }
        guard let language = normalized.split(separator: "-").first.map(String.init) else { return nil }
        return supported.first { $0.identifier.lowercased().hasPrefix(language.lowercased() + "-") }
    }
}
