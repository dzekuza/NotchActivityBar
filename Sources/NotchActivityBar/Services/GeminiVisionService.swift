import Foundation

/// Extracts verbatim text from an image via Gemini's REST `generateContent`
/// endpoint (same shape as `GeminiSummaryService`, with an inline image part
/// added alongside the prompt). Link detection isn't asked of the model —
/// it's done locally with `NSDataDetector` on the returned text, which is
/// more reliable than depending on the model to follow a formatting
/// convention.
enum GeminiVisionService {
    private static let model = "gemini-3.5-flash-lite"

    struct VisionError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func extractText(imageData: Data, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
            throw VisionError(message: "Invalid Gemini API URL")
        }

        let prompt = """
        Extract all readable text from this screenshot, verbatim, preserving line breaks. If there is no readable text, respond with exactly "No text detected."
        """

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "image/png", "data": imageData.base64EncodedString()]],
                ]],
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
            throw VisionError(message: message ?? "Gemini text extraction request failed")
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let first = candidates.first,
            let content = first["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            throw VisionError(message: "Unexpected Gemini response format")
        }

        let text = parts.compactMap { $0["text"] as? String }.joined()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw VisionError(message: "Empty extraction response")
        }
        return trimmed
    }
}
