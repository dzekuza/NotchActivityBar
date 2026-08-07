import SwiftUI

struct NoteCardScrollView: View {
    let notes: [NoteItem]
    let onDelete: (NoteItem) -> Void

    var body: some View {
        Group {
            if notes.isEmpty {
                EmptyStateView(
                    systemImage: "note.text",
                    title: "No notes yet",
                    subtitle: "Jot something down above to save it here"
                )
                .frame(width: Theme.expandedWidth)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(notes) { note in
                            NoteCardView(note: note) {
                                onDelete(note)
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
        .animation(.snappy(duration: 0.3), value: notes)
        .frame(height: Theme.cardImageHeight + 60)
    }
}
