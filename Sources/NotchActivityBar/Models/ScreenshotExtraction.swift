import Foundation

/// Result of an AI text/link extraction pass over one screenshot, keyed by
/// the screenshot's file URL in `ScreenshotMonitor.extractionStates` (the
/// `ScreenshotItem` struct itself is recreated on every Spotlight refresh,
/// so this can't live on the item).
enum ScreenshotExtractionState: Equatable {
    case loading
    case success(text: String, links: [URL])
    case failure(String)
}
