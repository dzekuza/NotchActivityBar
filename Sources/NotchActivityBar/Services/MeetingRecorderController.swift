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
    private(set) var activeTranscriber: GeminiLiveTranscriber?

    /// Fired whenever `isRecording` flips, for non-SwiftUI observers (the notch banner).
    var onRecordingStateChange: ((Bool) -> Void)?

    private let apiKeyStore: GeminiAPIKeyStore
    private let callActivityDetector = CallActivityDetector()
    private var audioCapture: MeetingAudioCapture?
    private var currentSession: MeetingSession?

    init(apiKeyStore: GeminiAPIKeyStore) {
        self.apiKeyStore = apiKeyStore
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

    private func startRecording() {
        guard !isRecording else { return }
        guard let apiKey = apiKeyStore.apiKey, !apiKey.isEmpty else {
            lastError = "No Gemini API key set — add one from the menu bar icon."
            return
        }

        let transcriber = GeminiLiveTranscriber(apiKey: apiKey)
        let capture = MeetingAudioCapture()
        capture.onPCMChunk = { [weak transcriber] data in
            transcriber?.send(pcmChunk: data)
        }
        // The system can end the capture behind our back (user clicks "Stop
        // Sharing" in the menu bar indicator) — tear down the whole session.
        capture.onStreamStopped = { [weak self] in
            self?.stopRecording()
        }

        activeTranscriber = transcriber
        audioCapture = capture
        currentSession = MeetingSession(id: UUID(), startedAt: Date(), endedAt: nil, transcript: "")
        lastError = nil

        transcriber.connect()

        Task { @MainActor in
            do {
                try await capture.start()
                // Stop was pressed while the capture was still starting up —
                // don't resurrect the session; kill the freshly started capture.
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
            session.transcript = activeTranscriber?.transcript ?? ""
            if !session.transcript.isEmpty {
                MeetingSessionStore.save(session)
                pastSessions.insert(session, at: 0)
            }
        }
        currentSession = nil

        activeTranscriber?.disconnect()
        activeTranscriber = nil

        isRecording = false
        onRecordingStateChange?(false)
    }
}
