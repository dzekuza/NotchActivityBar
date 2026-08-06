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
        guard !isRecording else { return }
        guard let apiKey = apiKeyStore.apiKey, !apiKey.isEmpty else {
            lastError = "No Gemini API key set — add one from the menu bar icon."
            return
        }

        let transcriber = GeminiLiveTranscriber(apiKey: apiKey)
        transcriber.onError = { [weak self] errorMsg in
            Task { @MainActor in
                self?.lastError = "Gemini Live: \(errorMsg)"
            }
        }

        let capture = MeetingAudioCapture()
        capture.onPCMChunk = { [weak transcriber] data in
            transcriber?.send(pcmChunk: data)
        }
        capture.onStreamStopped = { [weak self] in
            self?.stopRecording()
        }

        activeTranscriber = transcriber
        audioCapture = capture
        currentSession = MeetingSession(id: UUID(), startedAt: Date(), endedAt: nil, transcript: "")
        lastError = nil

        transcriber.connect()

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
            let rawTranscript = activeTranscriber?.transcript.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            session.transcript = rawTranscript.isEmpty ? "Audio recording completed" : rawTranscript
            MeetingSessionStore.save(session)
            pastSessions.insert(session, at: 0)
        }
        currentSession = nil

        activeTranscriber?.disconnect()
        activeTranscriber = nil

        isRecording = false
        onRecordingStateChange?(false)
    }
}
