import SwiftUI

struct ClipboardCardScrollView: View {
    let items: [ClipboardItem]
    let onCopy: (ClipboardItem) -> Void
    let onDelete: (ClipboardItem) -> Void

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyStateView(
                    systemImage: "doc.on.clipboard",
                    title: "Nothing copied yet",
                    subtitle: "Items you copy will show up here"
                )
                .frame(width: Theme.expandedWidth)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(items) { item in
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
        .frame(height: Theme.cardImageHeight + 60)
    }
}
