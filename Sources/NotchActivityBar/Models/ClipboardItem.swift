import AppKit
import Foundation
import SwiftUI

enum ClipboardKind {
    case text
    case color
    case link
    case image
}

struct ClipboardItem: Identifiable, Equatable {
    let id = UUID()
    let kind: ClipboardKind
    let title: String
    let subtitle: String
    let copiedAt: Date
    let thumbnail: NSImage?

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.kind == rhs.kind && lhs.title == rhs.title
    }

    var relativeTime: String {
        RelativeTimeFormatter.short(from: copiedAt)
    }

    var iconSystemName: String {
        switch kind {
        case .text: "textformat"
        case .color: "eyedropper"
        case .link: "link"
        case .image: "photo"
        }
    }

    var swatchColor: Color? {
        guard kind == .color else { return nil }
        return Color(hex: title)
    }
}
