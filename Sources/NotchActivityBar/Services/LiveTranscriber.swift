import Foundation

/// One recognized word (or short utterance) with the wall-clock window it was
/// spoken in, so `SpeakerTimeline` can say who was talking at the time. The
/// Speech framework reports segment timings relative to the start of the audio
/// it has been fed; the transcriber converts those to absolute dates.
struct TimedTranscriptWord: Equatable {
    let text: String
    let startedAt: Date
    let endedAt: Date
}

/// Common surface for the two transcription engines (`AppleSpeechTranscriber`,
/// `GeminiLiveTranscriber`) so `MeetingRecorderController` can swap between
/// them — including switching mid-recording if one fails.
@MainActor
protocol LiveTranscriber: AnyObject {
    var transcript: String { get }
    var isConnected: Bool { get }
    var lastError: String? { get }
    var onError: ((String) -> Void)? { get set }

    func connect()
    func disconnect()
    func send(pcmChunk: Data)
}

extension LiveTranscriber {
    /// Empty for engines that stream plain text with no timing (Gemini Live).
    /// Those transcripts get sentence breaks but no speaker labels.
    var timedWords: [TimedTranscriptWord] { [] }
}
