import Foundation

struct NoteItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }

    var relativeTime: String {
        RelativeTimeFormatter.short(from: createdAt)
    }
}
