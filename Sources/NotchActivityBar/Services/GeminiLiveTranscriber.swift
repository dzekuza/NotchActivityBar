import Foundation
import Observation

private final class LiveWebSocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    var onOpen: (@Sendable () -> Void)?
    var onClose: (@Sendable () -> Void)?
    var onError: (@Sendable (String) -> Void)?

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        onOpen?()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        onClose?()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            onError?(error.localizedDescription)
        }
    }
}

/// Streams 16kHz mono PCM audio to Gemini's Live (BidiGenerateContent) API over
/// a WebSocket and accumulates the input-audio transcript as it comes back.
@MainActor
@Observable
final class GeminiLiveTranscriber: NSObject {
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
    var logRawFrames = true

    private let apiKey: String
    private let model: String
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var wsDelegate: LiveWebSocketDelegate?
    private var isSocketOpen = false
    private var pendingPayloads: [String] = []

    init(apiKey: String, model: String = "models/gemini-2.0-flash-exp") {
        self.apiKey = apiKey
        self.model = model
    }

    func connect() {
        guard webSocketTask == nil else { return }
        guard let url = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(apiKey)") else {
            lastError = "Invalid Gemini Live URL"
            return
        }

        let delegate = LiveWebSocketDelegate()
        wsDelegate = delegate

        delegate.onOpen = { [weak self] in
            Task { @MainActor in
                self?.handleSocketOpen()
            }
        }

        delegate.onClose = { [weak self] in
            Task { @MainActor in
                self?.isSocketOpen = false
                self?.isConnected = false
            }
        }

        delegate.onError = { [weak self] errorMsg in
            Task { @MainActor in
                self?.lastError = errorMsg
                self?.isConnected = false
            }
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        urlSession = session
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        receiveNext()
        sendSetup()
    }

    private func handleSocketOpen() {
        isSocketOpen = true
        isConnected = true
        lastError = nil

        let payloadsToFlush = pendingPayloads
        pendingPayloads.removeAll()
        for payload in payloadsToFlush {
            sendString(payload)
        }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        wsDelegate = nil
        isSocketOpen = false
        isConnected = false
        pendingPayloads.removeAll()
    }

    func resetTranscript() {
        transcript = ""
    }

    func send(pcmChunk: Data) {
        let message: [String: Any] = [
            "realtimeInput": [
                "mediaChunks": [
                    ["mimeType": "audio/pcm;rate=16000", "data": pcmChunk.base64EncodedString()],
                ],
            ],
        ]
        sendJSON(message)
    }

    private func sendSetup() {
        let setup: [String: Any] = [
            "setup": [
                "model": model,
                "generationConfig": [
                    "responseModalities": ["TEXT"],
                    "inputAudioTranscription": [String: Any](),
                ],
                "inputAudioTranscription": [String: Any](),
                "systemInstruction": [
                    "parts": [
                        ["text": "You are a silent transcription engine for live audio. Do not respond conversationally, do not summarize, do not answer questions asked in the audio — only transcribe what is said, verbatim, as it happens."],
                    ],
                ],
            ],
        ]
        sendJSON(setup)
    }

    private func sendJSON(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8)
        else { return }

        if isSocketOpen {
            sendString(string)
        } else {
            if pendingPayloads.count > 30 {
                pendingPayloads.remove(at: 1)
            }
            pendingPayloads.append(string)
        }
    }

    private func sendString(_ string: String) {
        guard let webSocketTask else { return }
        webSocketTask.send(.string(string)) { [weak self] error in
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
                Task { @MainActor in
                    self.lastError = error.localizedDescription
                    self.isConnected = false
                }
            case .success(let message):
                Task { @MainActor in
                    self.handle(message: message)
                    self.receiveNext()
                }
            }
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

        let serverContent = (json["serverContent"] as? [String: Any]) ?? (json["server_content"] as? [String: Any])
        guard let serverContent else { return }

        let inputTranscription = (serverContent["inputTranscription"] as? [String: Any]) ?? (serverContent["input_transcription"] as? [String: Any])
        if let inputTranscription, let text = inputTranscription["text"] as? String, !text.isEmpty {
            transcript += text
            return
        }

        let modelTurn = (serverContent["modelTurn"] as? [String: Any]) ?? (serverContent["model_turn"] as? [String: Any])
        if let modelTurn, let parts = modelTurn["parts"] as? [[String: Any]] {
            for part in parts {
                if let text = part["text"] as? String, !text.isEmpty {
                    transcript += text
                }
            }
        }
    }
}
