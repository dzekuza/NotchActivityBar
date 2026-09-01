import Foundation

/// Who said a stretch of transcript.
///
/// Attribution is by audio *channel*, not by voice: the microphone is you, and
/// everything captured from system audio is the far end. That's exact for a 1:1
/// call and can't be fooled by similar-sounding voices — but every remote
/// participant shares the one system-audio stream, so a group call collapses to
/// a single `.other`. Telling two remote people apart would need a real
/// diarizer, which the on-device Speech framework doesn't provide.
enum MeetingSpeaker: String, Codable, Equatable {
    case you
    case other

    var label: String {
        switch self {
        case .you: "You"
        case .other: "Other"
        }
    }
}

/// One speaker's uninterrupted stretch of transcript. `text` is already broken
/// into one sentence per line by `MeetingTranscriptFormatter`.
struct TranscriptSegment: Identifiable, Equatable, Codable {
    var id: Int { index }

    /// Position in the transcript. Stable within a session, which is all
    /// `Identifiable` needs here, and keeps the type `Codable` without
    /// persisting a UUID that would change on every re-render.
    let index: Int

    /// `nil` when the engine gave no timing to attribute against — Gemini Live
    /// streams plain text with no timestamps, so those transcripts get sentence
    /// breaks but no speaker labels.
    let speaker: MeetingSpeaker?
    var text: String
}
