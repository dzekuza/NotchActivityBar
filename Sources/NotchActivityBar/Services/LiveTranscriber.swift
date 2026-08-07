import Foundation

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
