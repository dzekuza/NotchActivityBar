import SwiftUI

struct TabPillBarView: View {
    @Binding var selection: AppTab
    let counts: [AppTab: Int]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = tab }
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .medium))
                        if let count = counts[tab], count > 0 {
                            Text("\(count)")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(selection == tab ? Theme.activeTabText.opacity(0.5) : Theme.inactiveTabCountText)
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
    }
}
