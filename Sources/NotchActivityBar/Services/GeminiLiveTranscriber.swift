import Foundation
import Observation

/// Streams 16kHz mono PCM audio to Gemini's Live (BidiGenerateContent) API over
/// a WebSocket and accumulates the input-audio transcript as it comes back.
///
/// Notes on the wire format (checked against docs current as of Aug 2026 —
/// this is a preview API and field names/models have shifted before, see the
/// old `git log` entry for this file):
/// - `responseModalities` MUST be `["AUDIO"]`. Sending `["TEXT"]` alone makes
///   the server close the connection with an "Invalid Argument" error — that
///   was the bug that broke the original integration. We never play the
///   returned audio; we only read `serverContent.inputTranscription`.
/// - Audio-only Live sessions are capped ~15 min without extra config, so we
///   enable `contextWindowCompression` (sliding window) and
///   `sessionResumption`, and transparently reconnect using the resumption
///   handle on `GoAway`/socket failure so a full meeting isn't cut short.
@MainActor
@Observable
final class GeminiLiveTranscriber: NSObject, LiveTranscriber {
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

    var logRawFrames = false

    private let apiKey: String
    private let model: String
    private let languageCode: String

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var resumptionHandle: String?
    private var isReconnecting = false
    private var shouldStayConnected = false

    /// Whether this connection attempt has ever received *any* server
    /// message — proof the setup message was accepted. If every attempt
    /// dies before this happens, the server is rejecting our setup (bad
    /// model/config/key), not hitting a transient network blip, so we stop
    /// retrying and surface the error instead of looping silently forever.
    private var hasReceivedServerMessage = false
    private var consecutiveFailedAttempts = 0
    private static let maxConsecutiveFailedAttempts = 3

    init(apiKey: String, languageCode: String = "", model: String = "models/gemini-3.1-flash-live-preview") {
        self.apiKey = apiKey
        self.languageCode = languageCode
        self.model = model
    }

    func connect() {
        shouldStayConnected = true
        openSocket()
    }

    func disconnect() {
        shouldStayConnected = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        isConnected = false
    }

    func resetTranscript() {
        transcript = ""
    }

    func send(pcmChunk: Data) {
        guard let webSocketTask else { return }
        // `realtimeInput.mediaChunks` was removed server-side (confirmed via a
        // close-code 1007 "media_chunks is deprecated. Use audio, video, or
        // text instead." rejection) — `audio` is the current field.
        let message: [String: Any] = [
            "realtimeInput": [
                "audio": ["mimeType": "audio/pcm;rate=16000", "data": pcmChunk.base64EncodedString()],
            ],
        ]
        sendJSON(message, over: webSocketTask)
    }

    private func openSocket() {
        guard let url = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(apiKey)") else {
            lastError = "Invalid Gemini Live URL"
            return
        }

        hasReceivedServerMessage = false
        let session = URLSession(configuration: .default)
        urlSession = session
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        NSLog("GeminiLiveTranscriber: opening socket, model=\(model), attempt=\(consecutiveFailedAttempts + 1)")
        sendSetup()
        receiveNext()
        isConnected = true
        lastError = nil
    }

    private func sendSetup() {
        guard let webSocketTask else { return }

        var instruction = "You are a silent transcription engine for a live call. Do not respond conversationally, do not summarize, do not answer questions asked in the audio — only transcribe what is said, verbatim, as it happens."
        if !languageCode.isEmpty {
            instruction += " The speaker is primarily speaking \(languageCode) — transcribe in that language rather than translating."
        }

        var generationConfig: [String: Any] = ["responseModalities": ["AUDIO"]]
        if !languageCode.isEmpty {
            generationConfig["speechConfig"] = ["languageCode": languageCode]
        }

        var setupBody: [String: Any] = [
            "model": model,
            "generationConfig": generationConfig,
            "inputAudioTranscription": [String: Any](),
            "contextWindowCompression": ["slidingWindow": [String: Any]()],
            "sessionResumption": [String: Any](),
            "systemInstruction": [
                "parts": [["text": instruction]],
            ],
        ]
        if let resumptionHandle {
            setupBody["sessionResumption"] = ["handle": resumptionHandle]
        }

        sendJSON(["setup": setupBody], over: webSocketTask)
    }

    private func sendJSON(_ object: [String: Any], over task: URLSessionWebSocketTask) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8)
        else { return }
        task.send(.string(string)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.lastError = "send failed: \(error.localizedDescription)"
            }
        }
    }

    private func receiveNext() {
        guard let webSocketTask else { return }
        webSocketTask.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                let closeCode = webSocketTask.closeCode
                let closeReason = webSocketTask.closeReason.flatMap { String(data: $0, encoding: .utf8) }
                Task { @MainActor in
                    self.handleSocketFailure(error.localizedDescription, closeCode: closeCode, closeReason: closeReason)
                }
            case .success(let message):
                Task { @MainActor in
                    self.hasReceivedServerMessage = true
                    self.consecutiveFailedAttempts = 0
                    self.handle(message: message)
                    self.receiveNext()
                }
            }
        }
    }

    private func handleSocketFailure(_ description: String, closeCode: URLSessionWebSocketTask.CloseCode = .invalid, closeReason: String? = nil) {
        isConnected = false
        webSocketTask = nil
        urlSession = nil
        guard shouldStayConnected else { return }

        NSLog("GeminiLiveTranscriber: socket failure — \(description); closeCode=\(closeCode.rawValue) closeReason=\(closeReason ?? "nil"); everConnected=\(hasReceivedServerMessage); attempt=\(consecutiveFailedAttempts)")

        // An explicit close reason means the server told us exactly what was
        // wrong with our request (bad field, invalid argument, etc.) — that
        // will fail identically on every retry, so stop immediately instead
        // of looping. A close with no reason (dropped connection, DNS
        // hiccup, etc.) is worth a few retries since it may be transient.
        if let closeReason, !closeReason.isEmpty {
            shouldStayConnected = false
            lastError = "Gemini Live rejected the connection: \(closeReason)"
            return
        }

        consecutiveFailedAttempts += 1
        if consecutiveFailedAttempts >= Self.maxConsecutiveFailedAttempts {
            shouldStayConnected = false
            lastError = "Gemini Live never accepted the connection (closeCode=\(closeCode.rawValue)) — check the API key and model access at aistudio.google.com."
            return
        }
        reconnect()
    }

    private func reconnect() {
        guard shouldStayConnected, !isReconnecting else { return }
        isReconnecting = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            self.isReconnecting = false
            guard self.shouldStayConnected else { return }
            self.openSocket()
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let raw): data = raw
        case .string(let text): data = Data(text.utf8)
        @unknown default: return
        }

        if logRawFrames, let text = String(data: data, encoding: .utf8) {
            NSLog("GeminiLiveTranscriber: raw frame — \(text)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            lastError = message
            return
        }

        if let goAway = json["goAway"] as? [String: Any] {
            let timeLeft = goAway["timeLeft"] as? String ?? "unknown"
            NSLog("GeminiLiveTranscriber: server sent goAway, timeLeft=\(timeLeft) — reconnecting proactively")
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            handleSocketFailure("server requested reconnect")
            return
        }

        if let update = json["sessionResumptionUpdate"] as? [String: Any],
           let handle = update["newHandle"] as? String,
           (update["resumable"] as? Bool) ?? true {
            resumptionHandle = handle
        }

        guard let serverContent = json["serverContent"] as? [String: Any] else { return }

        if let inputTranscription = serverContent["inputTranscription"] as? [String: Any],
           let text = inputTranscription["text"] as? String, !text.isEmpty {
            transcript += text
        }
    }
}
