import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class MeetingRecorderController {
    private(set) var isRecording = false
    private(set) var isAutoDetectEnabled = true
    private(set) var lastError: String?
    private(set) var pastSessions: [MeetingSession] = []

    /// While recording, observe `activeTranscriber?.transcript` for the live text.
    private(set) var activeTranscriber: (any LiveTranscriber)?

    let aiSettings = MeetingAISettings()
    let apiKeyStore = GeminiAPIKeyStore()

    /// Fired whenever `isRecording` flips, for non-SwiftUI observers (the notch banner).
    var onRecordingStateChange: ((Bool) -> Void)?

    private let callActivityDetector = CallActivityDetector()
    private var audioCapture: MeetingAudioCapture?
    private var currentSession: MeetingSession?

    /// Text already accumulated from a transcriber we fell back away from
    /// mid-recording (e.g. Gemini Live failing over to Apple Speech), so the
    /// final transcript doesn't lose what was captured before the switch.
    private var carriedOverTranscript = ""

    init() {
        pastSessions = MeetingSessionStore.loadAll()
    }

    func start() {
        callActivityDetector.onChange = { [weak self] active in
            guard let self, self.isAutoDetectEnabled else { return }
            if active {
                self.startRecording()
            } else {
                self.stopRecording()
            }
        }
        callActivityDetector.start()
    }

    func stop() {
        callActivityDetector.stop()
        stopRecording()
    }

    func setAutoDetectEnabled(_ enabled: Bool) {
        isAutoDetectEnabled = enabled
        if !enabled {
            stopRecording()
        }
    }

    /// Manual override, usable regardless of auto-detect.
    func toggleManually() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func deleteSession(_ session: MeetingSession) {
        MeetingSessionStore.delete(session)
        pastSessions.removeAll { $0.id == session.id }
    }

    private static func ensureMicrophoneAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func startRecording() {
        guard !isRecording, audioCapture == nil else { return }

        carriedOverTranscript = ""
        let transcriber = makeTranscriber()
        activeTranscriber = transcriber
        transcriber.connect()

        let capture = MeetingAudioCapture()
        // Route through `self.activeTranscriber` (not the local `transcriber`
        // directly) so a mid-recording fallback swap keeps receiving audio.
        capture.onPCMChunk = { [weak self] data in
            self?.activeTranscriber?.send(pcmChunk: data)
        }
        capture.onStreamStopped = { [weak self] in
            self?.stopRecording()
        }

        audioCapture = capture
        currentSession = MeetingSession(id: UUID(), startedAt: Date(), endedAt: nil, transcript: "")
        lastError = nil

        Task { @MainActor in
            let micAuthorized = await Self.ensureMicrophoneAuthorization()
            guard micAuthorized else {
                self.lastError = "Microphone access denied — enable it in System Settings > Privacy & Security > Microphone."
                self.stopRecording()
                return
            }

            do {
                let deviceID = AudioDeviceManager.shared.selectedDeviceID
                try await capture.start(inputDeviceID: deviceID)
                guard self.audioCapture === capture else {
                    capture.stop()
                    return
                }
                self.isRecording = true
                self.onRecordingStateChange?(true)
            } catch {
                guard self.audioCapture === capture else { return }
                self.lastError = "Failed to start audio capture — \(error.localizedDescription)"
                self.stopRecording()
            }
        }
    }

    private func stopRecording() {
        guard isRecording || audioCapture != nil else { return }

        audioCapture?.stop()
        audioCapture = nil

        if var session = currentSession {
            session.endedAt = Date()
            let liveTranscript = activeTranscriber?.transcript ?? ""
            let rawTranscript = (carriedOverTranscript + liveTranscript).trimmingCharacters(in: .whitespacesAndNewlines)
            session.transcript = rawTranscript.isEmpty ? "Audio recording completed" : rawTranscript
            MeetingSessionStore.save(session)
            pastSessions.insert(session, at: 0)
            requestSummary(for: session)
        }
        currentSession = nil
        carriedOverTranscript = ""

        activeTranscriber?.disconnect()
        activeTranscriber = nil

        isRecording = false
        onRecordingStateChange?(false)
    }

    private func makeTranscriber() -> any LiveTranscriber {
        if aiSettings.engine == .geminiLive, let apiKey = apiKeyStore.apiKey, !apiKey.isEmpty {
            let transcriber = GeminiLiveTranscriber(apiKey: apiKey, languageCode: aiSettings.languageCode)
            transcriber.onError = { [weak self, weak transcriber] errorMsg in
                Task { @MainActor in
                    guard let self, let transcriber, self.activeTranscriber === transcriber else { return }
                    self.fallBackToAppleSpeech(reason: errorMsg)
                }
            }
            return transcriber
        }

        if aiSettings.engine == .geminiLive {
            lastError = "Gemini Live selected but no API key is configured — using Apple Speech instead. Add a key in Settings."
        }
        return makeAppleSpeechTranscriber()
    }

    private func makeAppleSpeechTranscriber() -> AppleSpeechTranscriber {
        let transcriber = AppleSpeechTranscriber()
        transcriber.onError = { [weak self] errorMsg in
            Task { @MainActor in
                self?.lastError = "Transcription: \(errorMsg)"
            }
        }
        return transcriber
    }

    /// Gemini Live hit an unrecoverable error (bad key, quota, invalid
    /// request) — switch to on-device transcription without losing whatever
    /// was already transcribed, or interrupting the recording itself.
    private func fallBackToAppleSpeech(reason: String) {
        guard currentSession != nil, let failing = activeTranscriber, !(failing is AppleSpeechTranscriber) else { return }

        carriedOverTranscript += failing.transcript
        failing.disconnect()

        let transcriber = makeAppleSpeechTranscriber()
        activeTranscriber = transcriber
        transcriber.connect()

        lastError = "Gemini Live failed (\(reason)) — switched to on-device transcription for the rest of this meeting."
    }

    private func requestSummary(for session: MeetingSession) {
        guard aiSettings.isSummaryEnabled, let apiKey = apiKeyStore.apiKey, !apiKey.isEmpty else { return }
        let transcript = session.transcript
        guard transcript.count > 20 else { return }

        Task { @MainActor in
            do {
                let summary = try await GeminiSummaryService.summarize(transcript: transcript, apiKey: apiKey)
                var updated = session
                updated.summary = summary
                MeetingSessionStore.save(updated)
                if let index = self.pastSessions.firstIndex(where: { $0.id == session.id }) {
                    self.pastSessions[index] = updated
                }
            } catch {
                NSLog("MeetingRecorderController: summary generation failed — \(error.localizedDescription)")
            }
        }
    }
}
