import Testing
@testable import NotchActivityBar

@Suite("Link detection")
@MainActor
struct LinkDetectionTests {
    @Test
    func detectsPlainURL() {
        let links = ScreenshotMonitor.detectLinks(in: "Check this out: https://example.com/page")
        #expect(links.map(\.absoluteString) == ["https://example.com/page"])
    }

    @Test
    func returnsEmptyForTextWithoutURL() {
        let links = ScreenshotMonitor.detectLinks(in: "Just some plain text with no links.")
        #expect(links.isEmpty)
    }

    @Test
    func detectsMultipleURLs() {
        let links = ScreenshotMonitor.detectLinks(in: "See https://example.com and https://swift.org for details.")
        #expect(links.count == 2)
        #expect(links.map(\.absoluteString) == ["https://example.com", "https://swift.org"])
    }
}
