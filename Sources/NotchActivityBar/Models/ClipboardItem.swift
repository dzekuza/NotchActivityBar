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
    let id: UUID
    let kind: ClipboardKind
    /// Display-only preview text — may be truncated (text) or a fixed label (image).
    let title: String
    let subtitle: String
    let copiedAt: Date
    let thumbnail: NSImage?
    /// Full, untruncated text content. Populated for `.text`; used to restore
    /// the exact original content on re-copy, since `title` may be a preview.
    let fullText: String?
    /// Raw TIFF data of the copied image. Populated for `.image`; used both to
    /// restore exact pixel data on re-copy and to distinguish two different
    /// images from each other (title alone is always the fixed string "Image").
    let imageData: Data?
    /// Fetched page title for `.link` items, via LinkPresentation. Nil while the
    /// fetch is pending or after it fails — `title` (the raw URL) is the fallback.
    let linkPreviewTitle: String?
    /// True once a `.link` preview fetch has finished without producing a
    /// thumbnail or title, so the UI can stop showing a loading spinner.
    let linkFetchFailed: Bool

    init(
        id: UUID = UUID(),
        kind: ClipboardKind,
        title: String,
        subtitle: String,
        copiedAt: Date,
        thumbnail: NSImage?,
        fullText: String?,
        imageData: Data?,
        linkPreviewTitle: String? = nil,
        linkFetchFailed: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.copiedAt = copiedAt
        self.thumbnail = thumbnail
        self.fullText = fullText
        self.imageData = imageData
        self.linkPreviewTitle = linkPreviewTitle
        self.linkFetchFailed = linkFetchFailed
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        guard lhs.kind == rhs.kind else { return false }
        switch lhs.kind {
        case .text: return lhs.fullText == rhs.fullText
        case .image: return lhs.imageData == rhs.imageData
        case .color, .link: return lhs.title == rhs.title
        }
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

    /// Host component of the copied URL (e.g. "example.com"), for `.link` items.
    var linkHost: String? {
        guard kind == .link else { return nil }
        return URL(string: title)?.host?.replacingOccurrences(of: "www.", with: "")
    }
}
