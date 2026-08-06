import SwiftUI

struct IdleNotchView: View {
    var size: CGSize = CGSize(width: Theme.idleWidth, height: Theme.idleHeight)
    var cornerRadius: CGFloat = 14

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: cornerRadius,
            topTrailingRadius: 0,
            style: .continuous
        )
        .fill(Theme.panelBackground)
        .overlay(alignment: .center) {
            Circle()
                .fill(Theme.amber)
                .frame(width: 6, height: 6)
                .shadow(color: Theme.amber.opacity(0.6), radius: 4)
        }
        .frame(width: size.width, height: size.height)
    }
}
