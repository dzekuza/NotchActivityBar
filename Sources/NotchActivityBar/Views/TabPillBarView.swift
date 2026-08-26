import SwiftUI

struct TabPillBarView: View {
    @Binding var selection: AppTab
    let counts: [AppTab: Int]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    // Deliberately *not* wrapped in `withAnimation`. Doing so
                    // put the tab content swap inside an animation transaction,
                    // so SwiftUI cross-faded the outgoing and incoming tabs —
                    // and while both were in the hierarchy the enclosing stack
                    // measured the union of their heights. Every intermediate
                    // value was reported up as a new panel height, restarting
                    // the window's resize animation frame after frame, which
                    // is what made the panel stutter on a tab switch. The pill
                    // styling below still animates via `.animation(value:)`;
                    // only the height-bearing content now swaps atomically.
                    selection = tab
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .medium))
                        if let count = counts[tab], count > 0 {
                            Text("\(count)")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(selection == tab ? Theme.activeTabText.opacity(0.5) : Theme.inactiveTabCountText)
                                .contentTransition(.numericText())
                                .animation(.snappy(duration: 0.25), value: count)
                        }
                    }
                    .foregroundStyle(selection == tab ? Theme.activeTabText : Theme.inactiveTabText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(selection == tab ? Theme.activeTabBackground : Theme.inactiveTabBackground)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}
