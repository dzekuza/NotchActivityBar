import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class MeetingRecorderController {
    private(set) var isRecording = false
    private(set) var isAutoDetectEnabled = true
    private(set) var lastError: String?

    /// Non-fatal problems with an otherwise-running recording — chiefly "we got
    /// your mic but not the other participants because Screen Recording isn't
    /// granted". Kept separate from `lastError` so the UI can show it without
    /// implying the recording failed.
    private(set) var lastWarning: String?
    private(set) var pastSessions: [MeetingSession] = []

    /// While recording, observe `activeTranscriber?.transcript` for the live text.
    private(set) var activeTranscriber: (any LiveTranscriber)?

    /// Speaker-attributed view of the in-progress recording, rebuilt as the
    /// transcript grows so the live card can show turns instead of a blob.
    private(set) var liveSegments: [TranscriptSegment] = []

    /// True for the first moments of a recording, while the notch offers a
    /// chance to correct the transcription language. Auto-detection is a guess
    /// and a wrong one costs the whole meeting, so the guess is shown rather
    /// than buried in Settings — but it dismisses itself so an unattended
    /// recording is never blocked on a click.
    private(set) var isAwaitingLanguageConfirmation = false {
        didSet {
            guard isAwaitingLanguageConfirmation != oldValue else { return }
            onLanguagePromptChange?(isAwaitingLanguageConfirmation)
        }
    }

    let aiSettings = MeetingAISettings()
    let apiKeyStore = GeminiAPIKeyStore()
    let permissions = PermissionsController()

    /// Fired whenever `isRecording` flips, for non-SwiftUI observers (the notch banner).
    var onRecordingStateChange: ((Bool) -> Void)?

    /// Mirrors `isAwaitingLanguageConfirmation` for the notch, which isn't a
    /// SwiftUI observer — same reason `onRecordingStateChange` exists. Fires on
    /// the self-dismiss timeout too, not just on user action.
    var onLanguagePromptChange: ((Bool) -> Void)?

    private let callActivityDetector = CallActivityDetector()
    private let speakerTimeline = SpeakerTimeline()

    /// Throttling for the live speaker view. Rebuilding it is O(transcript),
    /// and the level callback fires ten times a second — left ungated, an
    /// hour-long meeting would re-tokenize tens of thousands of words on every
    /// tick. The final transcript is built once, in full, at teardown.
    private var languagePromptTask: Task<Void, Never>?
    private let languagePromptTimeout: TimeInterval = 12

    private var lastLiveRefresh = Date.distantPast
    private var lastLiveWordCount = 0
    private let liveRefreshInterval: TimeInterval = 0.5

    /// How much of the tail the live card formats. It only shows the last few
    /// lines, so formatting the whole backlog every refresh buys nothing.
    private let liveSegmentWordWindow = 400

    /// Below this a transcript has nothing to summarize into bullet points.
    /// Roughly 30 seconds of speech.
    private let minimumWordsForSummary = 60
    private var audioCapture: MeetingAudioCapture?
    private var currentSession: MeetingSession?

    /// Whether the in-flight recording was started by the call detector rather
    /// than by the user. Only auto-started recordings are auto-stopped when the
    /// mic goes quiet — a deliberate "Record Now" runs until Stop is pressed.
    private var isAutoStartedSession = false

    /// Text already accumulated from a transcriber we fell back away from
    /// mid-recording (e.g. Gemini Live failing over to Apple Speech), so the
    /// final transcript doesn't lose what was captured before the switch.
    private var carriedOverTranscript = ""

    init() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pastSessions = await MeetingSessionStore.loadAll()
        }
    }

    func start() {
        callActivityDetector.onChange = { [weak self] active in
            guard let self, self.isAutoDetectEnabled else { return }
            if active {
                self.startRecording(auto: true)
            } else {
                guard self.isAutoStartedSession else { return }
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
        // Only tears down a recording auto-detect itself started; a manual one
        // is the user's, and switching the feature off shouldn't end it.
        if !enabled, isAutoStartedSession {
            stopRecording()
        }
    }

    var languageOptions: [MeetingLanguage] {
        MeetingLanguageCatalog.available(for: aiSettings.engine)
    }

    var selectedLanguageCode: String { aiSettings.languageCode }

    func confirmLanguage() {
        languagePromptTask?.cancel()
        languagePromptTask = nil
        isAwaitingLanguageConfirmation = false
    }

    /// Switches language mid-recording, discarding what was transcribed so far.
    ///
    /// Dropping it is deliberate: the prompt only appears in the opening
    /// seconds, and anything recognized before a correction was recognized in
    /// the wrong language, so it is worse than nothing. Restarting clean also
    /// keeps per-word timings intact, which speaker attribution needs — a
    /// carried-over transcript has none and would lose the labels.
    func changeLanguage(to code: String) {
        guard code != aiSettings.languageCode else {
            confirmLanguage()
            return
        }
        aiSettings.languageCode = code

        guard isRecording, currentSession != nil else {
            confirmLanguage()
            return
        }
        activeTranscriber?.disconnect()
        carriedOverTranscript = ""
        liveSegments = []
        lastLiveWordCount = 0
        lastLiveRefresh = .distantPast
        speakerTimeline.reset()

        let transcriber = makeTranscriber()
        activeTranscriber = transcriber
        transcriber.connect()
        confirmLanguage()
    }

    /// Manual override, usable regardless of auto-detect.
    func toggleManually() {
        if isRecording {
            stopRecording()
        } else {
            startRecording(auto: false)
        }
    }

    func deleteSession(_ session: MeetingSession) {
        pastSessions.removeAll { $0.id == session.id }
        Task { await MeetingSessionStore.delete(session) }
    }

    /// Always re-reads the live TCC status rather than trusting anything cached
    /// from an earlier recording: the user can revoke (or grant) microphone
    /// access in System Settings at any point between two recordings.
    private func ensureMicrophoneAuthorization() async -> Bool {
        permissions.refresh()
        switch permissions.microphone {
        case .granted:
            return true
        case .notDetermined:
            let granted = await PermissionPrompt.around { await AVCaptureDevice.requestAccess(for: .audio) }
            permissions.refresh()
            return granted
        case .denied:
            return false
        }
    }

    private func startRecording(auto: Bool) {
        guard !isRecording, audioCapture == nil else { return }

        carriedOverTranscript = ""
        liveSegments = []
        lastLiveRefresh = .distantPast
        lastLiveWordCount = 0
        speakerTimeline.reset()
        let transcriber = makeTranscriber()
        activeTranscriber = transcriber
        transcriber.connect()

        let capture = MeetingAudioCapture()
        // Route through `self.activeTranscriber` (not the local `transcriber`
        // directly) so a mid-recording fallback swap keeps receiving audio.
        capture.onPCMChunk = { [weak self] data in
            self?.activeTranscriber?.send(pcmChunk: data)
        }
        capture.onChannelLevels = { [weak self] mic, system in
            guard let self else { return }
            self.speakerTimeline.record(micLevel: mic, systemLevel: system, at: Date())
            self.refreshLiveSegments()
        }
        capture.onStreamStopped = { [weak self] error in
            guard let self else { return }
            if let error {
                self.lastError = "Recording stopped — \(error.localizedDescription)"
            }
            self.stopRecording()
        }

        audioCapture = capture
        currentSession = MeetingSession(id: UUID(), startedAt: Date(), endedAt: nil, transcript: "")
        isAutoStartedSession = auto
        lastError = nil
        lastWarning = nil

        Task { @MainActor in
            let micAuthorized = await self.ensureMicrophoneAuthorization()
            guard micAuthorized else {
                self.lastError = "Microphone access is turned off — turn it on in System Settings > Privacy & Security > Microphone, then try again."
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
                self.lastWarning = capture.systemAudioFailure
                self.isRecording = true
                self.beginLanguageConfirmation()
                self.onRecordingStateChange?(true)
            } catch {
                guard self.audioCapture === capture else { return }
                self.lastError = "Failed to start audio capture — \(error.localizedDescription)"
                self.stopRecording()
            }
        }
    }

    private func stopRecording() {
        guard let session = teardownRecording() else { return }
        Task { await MeetingSessionStore.save(session) }
        requestSummary(for: session)
    }

    /// Used from app-quit paths, where the process may exit before a
    /// fire-and-forget `Task` from `stopRecording()` gets to write the
    /// session to disk — this awaits the save so it's guaranteed to land.
    func stopAndWaitForPersistence() async {
        callActivityDetector.stop()
        guard let session = teardownRecording() else { return }
        await MeetingSessionStore.save(session)
    }

    @discardableResult
    private func teardownRecording() -> MeetingSession? {
        guard isRecording || audioCapture != nil else { return nil }

        audioCapture?.stop()
        audioCapture = nil

        var persistedSession: MeetingSession?
        if var session = currentSession {
            session.endedAt = Date()
            let liveTranscript = activeTranscriber?.transcript ?? ""
            let rawTranscript = (carriedOverTranscript + liveTranscript).trimmingCharacters(in: .whitespacesAndNewlines)
            let segments = buildSegments(rawTranscript: rawTranscript)
            session.segments = segments.isEmpty ? nil : segments
            let rendered = segments.isEmpty ? rawTranscript : MeetingTranscriptFormatter.plainText(from: segments)
            session.transcript = rendered.isEmpty ? "Audio recording completed" : rendered
            pastSessions.insert(session, at: 0)
            persistedSession = session
        }
        currentSession = nil
        isAutoStartedSession = false
        languagePromptTask?.cancel()
        languagePromptTask = nil
        isAwaitingLanguageConfirmation = false
        liveSegments = []
        speakerTimeline.reset()
        carriedOverTranscript = ""
        lastWarning = nil

        activeTranscriber?.disconnect()
        activeTranscriber = nil

        isRecording = false
        onRecordingStateChange?(false)
        return persistedSession
    }

    /// Speaker attribution needs per-word timings. A transcript carried over
    /// from a failed engine has none, so once a fallback has happened the whole
    /// thing degrades to sentence breaks only rather than mislabelling the
    /// carried-over half as whoever spoke most recently.
    private func buildSegments(rawTranscript: String) -> [TranscriptSegment] {
        let words = activeTranscriber?.timedWords ?? []
        guard !words.isEmpty, carriedOverTranscript.isEmpty else {
            return MeetingTranscriptFormatter.unattributedSegments(from: rawTranscript)
        }
        return MeetingTranscriptFormatter.segments(from: words, timeline: speakerTimeline)
    }

    private func beginLanguageConfirmation() {
        isAwaitingLanguageConfirmation = true
        languagePromptTask?.cancel()
        languagePromptTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.languagePromptTimeout ?? 12))
            guard !Task.isCancelled else { return }
            self?.isAwaitingLanguageConfirmation = false
        }
    }

    private func refreshLiveSegments() {
        let words = activeTranscriber?.timedWords ?? []
        let now = Date()
        guard words.count != lastLiveWordCount,
              now.timeIntervalSince(lastLiveRefresh) >= liveRefreshInterval
        else { return }
        lastLiveRefresh = now
        lastLiveWordCount = words.count

        guard !words.isEmpty, carriedOverTranscript.isEmpty else {
            liveSegments = MeetingTranscriptFormatter.unattributedSegments(
                from: carriedOverTranscript + (activeTranscriber?.transcript ?? "")
            )
            return
        }
        let tail = words.suffix(liveSegmentWordWindow)
        liveSegments = MeetingTranscriptFormatter.segments(from: Array(tail), timeline: speakerTimeline)
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
        let transcriber = AppleSpeechTranscriber(localeIdentifier: aiSettings.languageCode)
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
        // A handful of words is not a meeting. The old 20-character bar meant
        // every stray 10-second recording spent an API call only to be told
        // there was nothing to summarize.
        let wordCount = transcript.split(whereSeparator: \.isWhitespace).count
        guard wordCount >= minimumWordsForSummary else { return }

        Task { @MainActor in
            do {
                guard let summary = try await GeminiSummaryService.summarize(transcript: transcript, apiKey: apiKey) else { return }
                var updated = session
                updated.summary = summary
                await MeetingSessionStore.save(updated)
                if let index = self.pastSessions.firstIndex(where: { $0.id == session.id }) {
                    self.pastSessions[index] = updated
                }
            } catch {
                NSLog("MeetingRecorderController: summary generation failed — \(error.localizedDescription)")
            }
        }
    }
}
