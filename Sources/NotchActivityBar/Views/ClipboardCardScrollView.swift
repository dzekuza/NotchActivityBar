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
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(items) { item in
                            ClipboardCardView(item: item) {
                                onCopy(item)
                            } onDelete: {
                                onDelete(item)
                            }
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .scrollIndicators(.never)
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.3), value: items)
        .frame(height: Theme.cardImageHeight + 60)
    }
}
