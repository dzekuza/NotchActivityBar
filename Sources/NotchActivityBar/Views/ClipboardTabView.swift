import SwiftUI

enum ClipboardCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case links = "Links"
    case text = "Text"

    var id: String { rawValue }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .links: return item.kind == .link
        case .text: return item.kind == .text
        }
    }
}

struct ClipboardTabView: View {
    let monitor: ClipboardMonitor
    var searchText: String = ""

    @State private var category: ClipboardCategory = .all

    private var filteredItems: [ClipboardItem] {
        var result = monitor.items.filter { category.matches($0) }
        guard !searchText.isEmpty else { return result }
        result = result.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.subtitle.localizedCaseInsensitiveContains(searchText) ||
            ($0.linkPreviewTitle?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            categoryPicker
            ClipboardCardScrollView(items: filteredItems, isSearching: !searchText.isEmpty || category != .all) { item in
                monitor.copy(item)
            } onDelete: { item in
                monitor.delete(item)
            }
        }
    }

    private var categoryPicker: some View {
        HStack(spacing: 6) {
            ForEach(ClipboardCategory.allCases) { option in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { category = option }
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(category == option ? Theme.activeTabText : Theme.inactiveTabText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(category == option ? Theme.activeTabBackground : Theme.inactiveTabBackground)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }
}
