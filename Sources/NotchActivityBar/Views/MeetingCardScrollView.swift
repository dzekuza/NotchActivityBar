import SwiftUI

struct MeetingCardScrollView: View {
    let sessions: [MeetingSession]
    var isSearching: Bool = false
    let onDelete: (MeetingSession) -> Void

    var body: some View {
        Group {
            if sessions.isEmpty {
                EmptyStateView(
                    systemImage: isSearching ? "magnifyingglass" : "waveform",
                    title: isSearching ? "No matches" : "No meetings recorded yet",
                    subtitle: isSearching ? "Try a different search" : "Recording starts automatically when a call is detected"
                )
                .frame(width: Theme.expandedWidth)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(sessions) { session in
                            MeetingCardView(session: session) {
                                onDelete(session)
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
        .animation(.snappy(duration: 0.3), value: sessions)
        .frame(height: Theme.cardImageHeight + 60)
    }
}
