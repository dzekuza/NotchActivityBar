import AppKit
import Foundation

struct ScreenshotItem: Identifiable, Equatable {
    let id: URL
    let url: URL
    let appName: String
    let capturedAt: Date
    var thumbnail: NSImage?

    var relativeTime: String {
        RelativeTimeFormatter.short(from: capturedAt)
    }

    static func == (lhs: ScreenshotItem, rhs: ScreenshotItem) -> Bool {
        lhs.id == rhs.id
    }
}
