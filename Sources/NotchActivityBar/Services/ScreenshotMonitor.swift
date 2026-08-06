@preconcurrency import AppKit
import Observation
@preconcurrency import QuickLookThumbnailing

@MainActor
@Observable
final class ScreenshotMonitor: NSObject {
    private(set) var items: [ScreenshotItem] = []

    private let query = NSMetadataQuery()
    private let historyLimit = 12
    private var manuallyDeletedURLs: Set<URL> = []

    func start() {
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleQueryUpdate),
            name: .NSMetadataQueryDidFinishGathering, object: query
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleQueryUpdate),
            name: .NSMetadataQueryDidUpdate, object: query
        )

        query.start()
    }

    func stop() {
        query.stop()
        NotificationCenter.default.removeObserver(self)
    }

    func delete(_ item: ScreenshotItem) {
        manuallyDeletedURLs.insert(item.url)
        items.removeAll { $0.id == item.id }
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        } catch {
            NSLog("ScreenshotMonitor: failed to trash \(item.url.path) — \(error.localizedDescription)")
        }
    }

    @objc private func handleQueryUpdate(_ notification: Notification) {
        query.disableUpdates()
        defer { query.enableUpdates() }

        let rawResults = (0..<min(query.resultCount, historyLimit * 2)).compactMap { index -> ScreenshotItem? in
            guard let result = query.result(at: index) as? NSMetadataItem,
                  let path = result.value(forAttribute: NSMetadataItemPathKey) as? String
            else { return nil }
            let url = URL(fileURLWithPath: path)
            let date = result.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date ?? Date()
            return ScreenshotItem(id: url, url: url, appName: appName(for: url), capturedAt: date, thumbnail: nil)
        }

        Task { @MainActor in
            self.manuallyDeletedURLs.formIntersection(Set(rawResults.map(\.url)))
            let filtered = rawResults.filter { !self.manuallyDeletedURLs.contains($0.url) }
            self.items = Array(filtered.prefix(self.historyLimit))
            self.loadThumbnails(for: self.items)
        }
    }

    private func appName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        if let range = name.range(of: " at ") {
            return String(name[..<range.lowerBound]).replacingOccurrences(of: "Screenshot ", with: "Screenshot")
        }
        return "Screenshot"
    }

    private func loadThumbnails(for screenshots: [ScreenshotItem]) {
        let generator = QLThumbnailGenerator.shared
        for screenshot in screenshots {
            let request = QLThumbnailGenerator.Request(
                fileAt: screenshot.url,
                size: CGSize(width: 240, height: 152),
                scale: 2,
                representationTypes: .thumbnail
            )
            generator.generateBestRepresentation(for: request) { [weak self] representation, _ in
                guard let self, let representation else { return }
                Task { @MainActor in
                    guard let index = self.items.firstIndex(where: { $0.id == screenshot.id }) else { return }
                    self.items[index].thumbnail = representation.nsImage
                }
            }
        }
    }
}
