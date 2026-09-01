import Foundation

struct MeetingSession: Identifiable, Equatable, Codable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date?
    var transcript: String
    var summary: String?

    /// Speaker-attributed, sentence-broken form of `transcript`, which stays
    /// the flat rendering used for search, copy, and summarization. Optional
    /// because sessions recorded before speaker labels existed decode without
    /// it — those render as plain text.
    var segments: [TranscriptSegment]?

    var title: String {
        Self.titleFormatter.string(from: startedAt)
    }

    var durationLabel: String {
        let end = endedAt ?? Date()
        let seconds = max(0, Int(end.timeIntervalSince(startedAt)))
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
