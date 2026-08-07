import AppKit
import LinkPresentation

/// Fetches a rich preview (page title + hero/favicon image) for a copied URL
/// using LinkPresentation, the same framework macOS uses for Messages/Mail
/// link previews. Best-effort: any failure just yields a nil result.
enum LinkPreviewFetcher {
    static func fetchPreview(for url: URL) async -> (title: String?, image: NSImage?) {
        let provider = LPMetadataProvider()
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else {
            return (nil, nil)
        }
        var image = await loadImage(from: metadata.imageProvider)
        if image == nil {
            image = await loadImage(from: metadata.iconProvider)
        }
        return (metadata.title, image)
    }

    private static func loadImage(from itemProvider: NSItemProvider?) async -> NSImage? {
        guard let itemProvider, itemProvider.canLoadObject(ofClass: NSImage.self) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = itemProvider.loadObject(ofClass: NSImage.self) { object, _ in
                continuation.resume(returning: object as? NSImage)
            }
        }
    }
}
