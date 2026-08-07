import Foundation
import Observation

enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case appleSpeech
    case geminiLive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appleSpeech: return "Apple Speech (offline)"
        case .geminiLive: return "Gemini Live (more languages, needs API key)"
        }
    }
}

/// User-configurable preferences for meeting transcription/AI, backed by
/// `UserDefaults` (the Gemini API key itself lives in the Keychain, see
/// `GeminiAPIKeyStore`).
@MainActor
@Observable
final class MeetingAISettings {
    private enum Keys {
        static let engine = "meetingTranscriptionEngine"
        static let languageCode = "meetingTranscriptionLanguageCode"
        static let summaryEnabled = "meetingSummaryEnabled"
    }

    var engine: TranscriptionEngine {
        didSet { UserDefaults.standard.set(engine.rawValue, forKey: Keys.engine) }
    }

    /// BCP-47 code (e.g. "lt-LT") sent to Gemini Live to bias recognition, or
    /// empty to let the model auto-detect the spoken language.
    var languageCode: String {
        didSet { UserDefaults.standard.set(languageCode, forKey: Keys.languageCode) }
    }

    var isSummaryEnabled: Bool {
        didSet { UserDefaults.standard.set(isSummaryEnabled, forKey: Keys.summaryEnabled) }
    }

    init() {
        let defaults = UserDefaults.standard
        engine = TranscriptionEngine(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .appleSpeech
        languageCode = defaults.string(forKey: Keys.languageCode) ?? ""
        isSummaryEnabled = defaults.object(forKey: Keys.summaryEnabled) as? Bool ?? true
    }
}
