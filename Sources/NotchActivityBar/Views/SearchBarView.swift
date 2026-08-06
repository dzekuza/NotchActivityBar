import SwiftUI

struct SearchBarView: View {
    @Binding var text: String
    let onClearAll: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
                TextField("Search...", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primaryText)
            }

            Spacer(minLength: 12)

            Button(action: onClearAll) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.inactiveTabBackground))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
}
