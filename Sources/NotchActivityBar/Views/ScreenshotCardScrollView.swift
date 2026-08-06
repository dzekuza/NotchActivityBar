import SwiftUI

struct ScreenshotCardScrollView: View {
    let items: [ScreenshotItem]
    let onDelete: (ScreenshotItem) -> Void

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyStateView(
                    systemImage: "camera.viewfinder",
                    title: "No screenshots today",
                    subtitle: "⌘⇧5 to capture one"
                )
                .frame(width: Theme.expandedWidth)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(items) { item in
                            ScreenshotCardView(item: item) {
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
