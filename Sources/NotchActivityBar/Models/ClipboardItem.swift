import AppKit
import Foundation
import SwiftUI

enum ClipboardKind {
    case text
    case color
    case link
    case image
}

enum ClipboardFolder: String, CaseIterable, Identifiable {
    case websites = "Websites"
    case text = "Text"
    case images = "Images"
    case colors = "Colors"

    var id: String { rawValue }

    var iconSystemName: String {
        switch self {
        case .websites: "link"
        case .text: "textformat"
        case .images: "photo"
        case .colors: "eyedropper"
        }
    }
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

    /// The folder/tag this item is filed under, so links land under
    /// "Websites" separately from plain text, images, and colors.
    var folder: ClipboardFolder {
        switch kind {
        case .link: .websites
        case .text: .text
        case .image: .images
        case .color: .colors
        }
    }

    var linkURL: URL? {
        guard kind == .link else { return nil }
        return URL(string: title)
    }
}
