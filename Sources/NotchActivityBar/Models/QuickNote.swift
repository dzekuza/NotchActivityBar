import Foundation

struct QuickNote: Identifiable, Equatable, Codable {
    let id: UUID
    var text: String
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var relativeTime: String {
        RelativeTimeFormatter.short(from: updatedAt)
    }

    var preview: String {
        text.isEmpty ? "Empty note" : text
    }
}
