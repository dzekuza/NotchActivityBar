import AVFoundation
import Foundation
import Observation
import Speech

/// Streams 16kHz mono PCM audio into an on-device `SFSpeechRecognizer` session
/// and accumulates the recognized text as it comes back. Fully local — no
/// network calls, no API key.
@MainActor
@Observable
final class AppleSpeechTranscriber: NSObject, LiveTranscriber {
    private(set) var transcript = ""
    private(set) var isConnected = false
    private(set) var lastError: String? {
        didSet {
            if let lastError {
                onError?(lastError)
            }
        }
    }
    var onError: ((String) -> Void)?

    private let audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// Text already finalized by a recognition task we tore down and replaced
    /// (see `reconnectAfterStall`), so restarting recognition doesn't drop what
    /// was already transcribed before the stall.
    private var committedTranscript = ""
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3

    func connect() {
        guard recognitionRequest == nil else { return }

        // Check the recorded decision before asking. `requestAuthorization` was
        // previously called unconditionally on every recording start, and each
        // call ran `PermissionPrompt.activate()` — which promotes this
        // menu-bar-only app to `.regular` and forcibly activates it. On an
        // already-authorized Mac that meant every auto-started meeting stole
        // focus from whatever the user was doing (typically the call itself)
        // for no reason, since macOS was never going to show a prompt.
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            startRecognition()
            return
        case .denied, .restricted:
            NSLog("AppleSpeechTranscriber: speech recognition not authorized")
            lastError = "Speech recognition is turned off — turn it on in System Settings > Privacy & Security > Speech Recognition."
            return
        case .notDetermined:
            break
        @unknown default:
            break
        }

        // `@Sendable` is required here: Speech's completion handler isn't
        // annotated Sendable in its imported interface, so Swift otherwise
        // infers this closure as MainActor-isolated (since it's written inside
        // a MainActor class) — but Speech actually invokes it off the main
        // thread, which traps at runtime. Marking it explicitly breaks that
        // false inference; the inner Task does the real hop back to MainActor.
        PermissionPrompt.activate()
        SFSpeechRecognizer.requestAuthorization { @Sendable [weak self] status in
            NSLog("AppleSpeechTranscriber: authorization status=\(status.rawValue)")
            Task { @MainActor [weak self] in
                PermissionPrompt.restore()
                guard let self else { return }
                guard status == .authorized else {
                    self.lastError = "Speech recognition access denied — enable it in System Settings > Privacy & Security > Speech Recognition."
                    return
                }
                self.startRecognition()
            }
        }
    }

    private func startRecognition() {
        let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            lastError = "Speech recognizer unavailable"
            NSLog("AppleSpeechTranscriber: recognizer unavailable")
            return
        }
        NSLog("AppleSpeechTranscriber: starting recognition, supportsOnDeviceRecognition=\(recognizer.supportsOnDeviceRecognition)")
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request
        lastError = nil
        isConnected = true

        recognitionTask = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            // Pull out plain Sendable values here, off the main thread — the
            // SFSpeechRecognitionResult/Error types themselves aren't Sendable,
            // so only these get handed across the actor boundary below.
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let nsError = error.map { $0 as NSError }

            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text {
                    NSLog("AppleSpeechTranscriber: partial result — \(text)")
                    self.transcript = self.committedTranscript.isEmpty ? text : self.committedTranscript + " " + text
                    self.reconnectAttempts = 0
                }
                if let nsError {
                    // Recognizer cancellation (from our own disconnect()) surfaces as
                    // an error too — ignore it once we've already torn down.
                    guard self.recognitionRequest != nil else { return }
                    NSLog("AppleSpeechTranscriber: recognition error domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)")
                    if !isFinal {
                        // The task died without ever delivering a final result — left
                        // as-is, `send(pcmChunk:)` would keep appending audio into a
                        // request producing no further callbacks, silently freezing
                        // the transcript for the rest of the recording. Restart a
                        // fresh recognition task, carrying over what we already have.
                        self.reconnectAfterStall(errorDescription: nsError.localizedDescription)
                        return
                    }
                    self.lastError = nsError.localizedDescription
                }
                if isFinal {
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                    self.isConnected = false
                }
            }
        }
    }

    func disconnect() {
        NSLog("AppleSpeechTranscriber: disconnect() called")
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        recognizer = nil
        isConnected = false
        reconnectAttempts = 0
    }

    func resetTranscript() {
        transcript = ""
        committedTranscript = ""
    }

    private func reconnectAfterStall(errorDescription: String) {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        recognizer = nil

        guard reconnectAttempts < maxReconnectAttempts else {
            NSLog("AppleSpeechTranscriber: giving up after \(reconnectAttempts) reconnect attempts")
            lastError = "Speech recognition stopped — \(errorDescription)"
            isConnected = false
            return
        }
        reconnectAttempts += 1
        committedTranscript = transcript
        NSLog("AppleSpeechTranscriber: recognition task stalled (\(errorDescription)) — reconnecting, attempt \(reconnectAttempts)")
        startRecognition()
    }

    func send(pcmChunk: Data) {
        guard let recognitionRequest else { return }
        guard let buffer = Self.makeBuffer(from: pcmChunk, format: audioFormat) else {
            NSLog("AppleSpeechTranscriber: failed to build buffer from \(pcmChunk.count) bytes")
            return
        }
        recognitionRequest.append(buffer)
    }

    private static func makeBuffer(from data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return nil }
        let frameCount = data.count / bytesPerFrame
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let channelData = buffer.int16ChannelData else { return nil }
        data.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.baseAddress else { return }
            memcpy(channelData[0], source, frameCount * bytesPerFrame)
        }
        return buffer
    }
}
