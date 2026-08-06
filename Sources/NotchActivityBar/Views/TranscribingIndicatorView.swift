import SwiftUI

/// Three dots that pulse in sequence, signaling that on-device speech
/// recognition is actively listening but hasn't produced text yet.
struct TranscribingIndicatorView: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.amber)
                    .frame(width: 4, height: 4)
                    .opacity(isAnimating ? 1 : 0.25)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: isAnimating
                    )
            }
            Text("Transcribing…")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
        }
        .onAppear { isAnimating = true }
    }
}
