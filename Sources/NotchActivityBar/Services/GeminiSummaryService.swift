import Foundation

/// Summarizes a finished meeting transcript via Gemini's plain REST
/// `generateContent` endpoint — no WebSocket, no streaming, just a single
/// request/response after recording stops.
enum GeminiSummaryService {
    private static let model = "gemini-3.5-flash-lite"

    /// What the prompt tells the model to emit when there's nothing worth
    /// summarizing. It is a signal, not a summary — storing it as one is what
    /// put "No summary available." on meeting cards in place of the transcript
    /// preview that would actually have been useful.
    static let unavailableSentinel = "No summary available."

    /// Whether a stored summary is really the sentinel. Applied on read too, so
    /// sessions that already persisted it before this was caught display
    /// correctly without a migration.
    static func isUnavailable(_ summary: String) -> Bool {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.caseInsensitiveCompare(unavailableSentinel) == .orderedSame
    }

    struct SummaryError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Returns nil when the model declined to summarize — a transcript too
    /// short or too thin to say anything about.
    static func summarize(transcript: String, apiKey: String) async throws -> String? {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
            throw SummaryError(message: "Invalid Gemini API URL")
        }

        let prompt = """
        Summarize this meeting transcript in 3-6 concise bullet points, capturing decisions and action items. Skip small talk. If the transcript is empty or too short to summarize meaningfully, respond with exactly "\(unavailableSentinel)"

        Transcript:
        \(transcript)
        """

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": prompt]]],
            ],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String }
            throw SummaryError(message: message ?? "Gemini summary request failed")
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let first = candidates.first,
            let content = first["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            throw SummaryError(message: "Unexpected Gemini response format")
        }

        let text = parts.compactMap { $0["text"] as? String }.joined()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return isUnavailable(trimmed) ? nil : trimmed
    }
}
