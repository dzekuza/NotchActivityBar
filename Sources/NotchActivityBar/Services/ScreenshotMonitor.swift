@preconcurrency import AppKit
import Observation
@preconcurrency import QuickLookThumbnailing

@MainActor
@Observable
final class ScreenshotMonitor: NSObject {
    private(set) var items: [ScreenshotItem] = []
    private(set) var extractionStates: [URL: ScreenshotExtractionState] = [:]
    var onNewItem: ((ScreenshotItem) -> Void)?

    private let query = NSMetadataQuery()
    private let historyLimit = 12
    private var manuallyDeletedURLs: Set<URL> = []
    private var hasFinishedInitialGather = false

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
        requestProtectedFolderAccessIfNeeded()
    }

    /// Screenshots default-save to ~/Desktop, but users can retarget the location
    /// (`defaults write com.apple.screencapture location ...`, or the Screenshot app's
    /// Options menu) to somewhere else — often ~/Documents, ~/Downloads, or a custom
    /// folder. Desktop/Documents/Downloads are all TCC-protected: Spotlight silently
    /// omits their contents from query results for any app that hasn't been granted
    /// access, with no prompt shown. As with mic/camera/speech (see PermissionPrompt),
    /// this accessory app has no key window to attach that consent alert to, so the
    /// very first protected-folder read must happen while briefly promoted to a
    /// regular, active app. We warm all of the standard protected folders plus
    /// whatever custom location is currently configured.
    private func requestProtectedFolderAccessIfNeeded() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates = [
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Downloads"),
        ]
        if let configuredPath = CFPreferencesCopyAppValue(
            "location" as CFString, "com.apple.screencapture" as CFString
        ) as? String {
            candidates.append(URL(fileURLWithPath: (configuredPath as NSString).expandingTildeInPath))
        }

        PermissionPrompt.activate()
        Task.detached(priority: .utility) {
            for url in candidates {
                _ = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            }
            await MainActor.run { PermissionPrompt.restore() }
        }
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

    /// Extracts verbatim text (and any links found in it) from a screenshot
    /// via Gemini vision. Results are cached per-URL for the lifetime of the
    /// app so reopening the same screenshot's detail overlay doesn't re-spend
    /// an API call.
    func extractText(for item: ScreenshotItem, apiKey: String) {
        guard extractionStates[item.url] != .loading else { return }
        extractionStates[item.url] = .loading
        let url = item.url

        Task {
            do {
                let imageData = try await Task.detached(priority: .utility) { try Data(contentsOf: url) }.value
                let rawText = try await GeminiVisionService.extractText(imageData: imageData, apiKey: apiKey)
                let links = Self.detectLinks(in: rawText)
                self.extractionStates[url] = .success(text: rawText, links: links)
            } catch {
                self.extractionStates[url] = .failure(error.localizedDescription)
            }
        }
    }

    private static func detectLinks(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range).compactMap(\.url)
    }

    @objc private func handleQueryUpdate(_ notification: Notification) {
        query.disableUpdates()
        defer { query.enableUpdates() }

        let isInitialGather = notification.name == .NSMetadataQueryDidFinishGathering && !hasFinishedInitialGather

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
            let previousURLs = Set(self.items.map(\.url))
            let newlyAdded = filtered.filter { !previousURLs.contains($0.url) }

            self.items = Array(filtered.prefix(self.historyLimit))
            self.loadThumbnails(for: self.items)

            if isInitialGather {
                self.hasFinishedInitialGather = true
            } else if self.hasFinishedInitialGather, let latest = newlyAdded.first {
                self.onNewItem?(latest)
            }
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
