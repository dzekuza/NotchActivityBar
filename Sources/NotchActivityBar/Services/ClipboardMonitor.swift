import AppKit
import Observation

@MainActor
@Observable
final class ClipboardMonitor {
    private(set) var items: [ClipboardItem] = []

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let historyLimit = 20

    init() {
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollPasteboard() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func clear() {
        items.removeAll()
    }

    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
    }

    func copy(_ item: ClipboardItem) {
        pasteboard.clearContents()
        pasteboard.setString(item.title, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    private func pollPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let item = readCurrentItem() else { return }
        guard items.first != item else { return }

        items.insert(item, at: 0)
        if items.count > historyLimit {
            items.removeLast(items.count - historyLimit)
        }
    }

    private func readCurrentItem() -> ClipboardItem? {
        if let color = NSColor(from: pasteboard) {
            return ClipboardItem(
                kind: .color,
                title: color.hexString,
                subtitle: "Color · copied",
                copiedAt: Date(),
                thumbnail: nil
            )
        }

        if let imageData = pasteboard.data(forType: .tiff), let image = NSImage(data: imageData) {
            return ClipboardItem(
                kind: .image,
                title: "Image",
                subtitle: "\(Int(image.size.width))×\(Int(image.size.height)) · copied",
                copiedAt: Date(),
                thumbnail: image
            )
        }

        guard let string = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else { return nil }

        if let url = URL(string: string), let scheme = url.scheme, scheme.hasPrefix("http") {
            return ClipboardItem(
                kind: .link,
                title: string,
                subtitle: "Link · copied",
                copiedAt: Date(),
                thumbnail: nil
            )
        }

        let lineCount = string.components(separatedBy: .newlines).count
        let preview = string.count > 80 ? String(string.prefix(80)) + "…" : string
        return ClipboardItem(
            kind: .text,
            title: preview,
            subtitle: lineCount > 1 ? "\(lineCount) lines copied" : "Text copied",
            copiedAt: Date(),
            thumbnail: nil
        )
    }
}

private extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.deviceRGB) else { return "—" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
