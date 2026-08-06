import Foundation
import Observation

/// Streams 16kHz mono PCM audio to Gemini's Live (BidiGenerateContent) API over
/// a WebSocket and accumulates the input-audio transcript as it comes back.
///
/// Note: this talks to a preview/streaming Google API whose exact JSON field
/// names have shifted across releases (v1alpha → v1beta). If transcripts stop
/// arriving after a Gemini API update, `lastError`/console logs of raw frames
/// (via `logRawFrames`) are the place to check the wire format against current
/// docs and adjust `sendSetup`/`send(pcmChunk:)`/`handle(message:)`.
@MainActor
@Observable
final class GeminiLiveTranscriber: NSObject {
    private(set) var transcript = ""
    private(set) var isConnected = false
    private(set) var lastError: String?

    var logRawFrames = false

    private let apiKey: String
    private let model: String
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    init(apiKey: String, model: String = "models/gemini-2.0-flash-live-001") {
        self.apiKey = apiKey
        self.model = model
    }

    func connect() {
        guard webSocketTask == nil else { return }
        guard let url = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(apiKey)") else {
            lastError = "Invalid Gemini Live URL"
            return
        }

        let session = URLSession(configuration: .default)
        urlSession = session
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        sendSetup()
        receiveNext()
        isConnected = true
        lastError = nil
    }

    func disconnect() {
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
        let message: [String: Any] = [
            "realtimeInput": [
                "mediaChunks": [
                    ["mimeType": "audio/pcm;rate=16000", "data": pcmChunk.base64EncodedString()],
                ],
            ],
        ]
        sendJSON(message, over: webSocketTask)
    }

    private func sendSetup() {
        guard let webSocketTask else { return }
        let setup: [String: Any] = [
            "setup": [
                "model": model,
                "generationConfig": ["responseModalities": ["TEXT"]],
                "inputAudioTranscription": [String: Any](),
                "systemInstruction": [
                    "parts": [
                        ["text": "You are a silent transcription engine for a live call. Do not respond conversationally, do not summarize, do not answer questions asked in the audio — only transcribe what is said, verbatim, as it happens."],
                    ],
                ],
            ],
        ]
        sendJSON(setup, over: webSocketTask)
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

        guard let serverContent = json["serverContent"] as? [String: Any] else { return }

        if let inputTranscription = serverContent["inputTranscription"] as? [String: Any],
           let text = inputTranscription["text"] as? String, !text.isEmpty {
            transcript += text
            return
        }

        if let modelTurn = serverContent["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            for part in parts {
                if let text = part["text"] as? String, !text.isEmpty {
                    transcript += text
                }
            }
        }
    }
}
