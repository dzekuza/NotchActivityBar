import SwiftUI

struct PlaceholderTabView: View {
    let tab: AppTab

    private var systemImage: String {
        tab == .music ? "music.note" : "timer"
    }

    var body: some View {
        EmptyStateView(
            systemImage: systemImage,
            title: "\(tab.rawValue) coming soon",
            subtitle: "This tab isn't wired up yet"
        )
        .frame(width: Theme.expandedWidth, height: Theme.cardImageHeight + 60)
    }
}
