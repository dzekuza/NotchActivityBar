import AppKit
import LinkPresentation
import SwiftUI

/// Embeds a rich website preview (favicon/og:image + title) for a copied
/// link, using the system LinkPresentation renderer — the same preview
/// style Messages/Mail use for shared URLs.
struct LinkPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> LPLinkView {
        if let cached = LinkMetadataCache.shared.metadata(for: url) {
            return LPLinkView(metadata: cached)
        }

        let view = LPLinkView(url: url)
        LinkMetadataCache.shared.fetch(url) { metadata in
            guard let metadata else { return }
            view.metadata = metadata
        }
        return view
    }

    func updateNSView(_ nsView: LPLinkView, context: Context) {}
}

/// Caches fetched `LPLinkMetadata` per URL for the lifetime of the process
/// so re-rendering a card (e.g. on hover/scroll) doesn't re-fetch the page.
@MainActor
final class LinkMetadataCache {
    static let shared = LinkMetadataCache()

    private var cache: [URL: LPLinkMetadata] = [:]
    private var inFlight: Set<URL> = []

    func metadata(for url: URL) -> LPLinkMetadata? {
        cache[url]
    }

    func fetch(_ url: URL, completion: @escaping (LPLinkMetadata?) -> Void) {
        if let cached = cache[url] {
            completion(cached)
            return
        }
        guard !inFlight.contains(url) else { return }
        inFlight.insert(url)

        let provider = LPMetadataProvider()
        provider.startFetchingMetadata(for: url) { [weak self] metadata, _ in
            let box = FetchResultBox(metadata: metadata, completion: completion)
            Task { @MainActor in
                self?.inFlight.remove(url)
                if let metadata = box.metadata {
                    self?.cache[url] = metadata
                }
                box.completion(box.metadata)
            }
        }
    }
}

/// `LPLinkMetadata` and the completion closure aren't `Sendable`, but the
/// provider's callback fires on an arbitrary background queue and this hop
/// to the main actor is race-free by construction (single read, single use).
private struct FetchResultBox: @unchecked Sendable {
    let metadata: LPLinkMetadata?
    let completion: (LPLinkMetadata?) -> Void
}
