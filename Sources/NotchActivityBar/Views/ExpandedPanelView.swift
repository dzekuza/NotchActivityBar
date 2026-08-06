import AppKit
import SwiftUI

struct ExpandedPanelView: View {
    let clipboardMonitor: ClipboardMonitor
    let screenshotMonitor: ScreenshotMonitor
    @Binding var selectedTab: AppTab
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SearchBarView(text: $searchText, onClearAll: clearActiveTab)
            TabPillBarView(selection: $selectedTab, counts: [
                .clipboard: clipboardMonitor.items.count,
                .screenshots: screenshotMonitor.items.count,
            ])
            content
        }
        .frame(width: Theme.expandedWidth)
        .background(Theme.panelBackground, in: RoundedRectangle(cornerRadius: Theme.panelCornerRadius, style: .continuous))
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.height, initial: true) { _, newValue in
                        onHeightChange(newValue)
                    }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .clipboard:
            ClipboardCardScrollView(items: filteredClipboardItems) { item in
                clipboardMonitor.copy(item)
            } onDelete: { item in
                clipboardMonitor.delete(item)
            }
        case .screenshots:
            ScreenshotCardScrollView(items: filteredScreenshotItems) { item in
                screenshotMonitor.delete(item)
            }
        case .music, .timer:
            PlaceholderTabView(tab: selectedTab)
        }
    }

    private var filteredClipboardItems: [ClipboardItem] {
        guard !searchText.isEmpty else { return clipboardMonitor.items }
        return clipboardMonitor.items.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.subtitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredScreenshotItems: [ScreenshotItem] {
        guard !searchText.isEmpty else { return screenshotMonitor.items }
        return screenshotMonitor.items.filter { $0.appName.localizedCaseInsensitiveContains(searchText) }
    }

    private func clearActiveTab() {
        switch selectedTab {
        case .clipboard:
            clipboardMonitor.clear()
        case .screenshots, .music, .timer:
            break
        }
    }
}
