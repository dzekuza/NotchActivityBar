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
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(items) { item in
                            ScreenshotCardView(item: item) {
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
