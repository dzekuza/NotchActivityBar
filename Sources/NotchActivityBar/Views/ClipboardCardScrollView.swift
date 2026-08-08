import SwiftUI

struct ClipboardCardScrollView: View {
    let items: [ClipboardItem]
    let onCopy: (ClipboardItem) -> Void
    let onDelete: (ClipboardItem) -> Void

    @State private var selectedFolder: ClipboardFolder?

    private var filteredItems: [ClipboardItem] {
        guard let selectedFolder else { return items }
        return items.filter { $0.folder == selectedFolder }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !items.isEmpty {
                folderChips
            }

            if filteredItems.isEmpty {
                EmptyStateView(
                    systemImage: "doc.on.clipboard",
                    title: items.isEmpty ? "Nothing copied yet" : "Nothing in \(selectedFolder?.rawValue ?? "") yet",
                    subtitle: items.isEmpty ? "Items you copy will show up here" : "Copied items will be filed here"
                )
                .frame(width: Theme.expandedWidth)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(filteredItems) { item in
                            ClipboardCardView(item: item) {
                                onCopy(item)
                            } onDelete: {
                                onDelete(item)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .scrollIndicators(.never)
            }
        }
        .frame(height: Theme.cardImageHeight + 90)
    }

    private var folderChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                folderChip(title: "All", icon: "tray.full", isSelected: selectedFolder == nil) {
                    selectedFolder = nil
                }
                ForEach(ClipboardFolder.allCases) { folder in
                    let count = items.count { $0.folder == folder }
                    if count > 0 {
                        folderChip(title: folder.rawValue, icon: folder.iconSystemName, isSelected: selectedFolder == folder) {
                            selectedFolder = folder
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.never)
    }

    private func folderChip(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isSelected ? Theme.activeTabText : Theme.inactiveTabText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(isSelected ? Theme.activeTabBackground : Theme.inactiveTabBackground))
        }
        .buttonStyle(.plain)
    }
}
