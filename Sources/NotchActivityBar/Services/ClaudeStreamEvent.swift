import Foundation

/// One line of `claude -p --output-format stream-json` output, loosely
/// parsed — the real payload shapes (assistant content blocks especially)
/// are deeply nested and vary by block type, so this pulls out only what the
/// UI needs rather than modeling the full schema.
enum ClaudeStreamEvent {
    case initInfo(sessionId: String)
    case assistantText(String)
    case toolUse(id: String, name: String, inputSummary: String)
    case finalResult(String)
    case unknown
}

enum ClaudeStreamEventParser {
    static func parse(_ data: Data) -> ClaudeStreamEvent? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return nil }

        switch type {
        case "system":
            guard obj["subtype"] as? String == "init", let sessionId = obj["session_id"] as? String else { return .unknown }
            return .initInfo(sessionId: sessionId)

        case "assistant":
            guard let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { return .unknown }

            if let toolBlock = content.first(where: { $0["type"] as? String == "tool_use" }),
               let id = toolBlock["id"] as? String,
               let name = toolBlock["name"] as? String {
                let input = toolBlock["input"] as? [String: Any]
                let summary = input.map { $0.map { "\($0.key): \($0.value)" }.joined(separator: ", ") } ?? ""
                return .toolUse(id: id, name: name, inputSummary: summary)
            }

            let text = content
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
            return text.isEmpty ? .unknown : .assistantText(text)

        case "result":
            return .finalResult(obj["result"] as? String ?? "")

        default:
            return .unknown
        }
    }
}
