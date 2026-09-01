import SwiftUI

/// Renders a transcript as speaker turns — a label, then that turn's sentences
/// one per line — instead of the single merged block the recognizers hand back.
struct TranscriptSegmentsView: View {
    let segments: [TranscriptSegment]
    var textSize: CGFloat = 13
    var isSelectable = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(segments) { segment in
                VStack(alignment: .leading, spacing: 2) {
                    if let speaker = segment.speaker {
                        Text(speaker.label)
                            .font(.system(size: textSize - 3, weight: .semibold))
                            .foregroundStyle(speaker == .you ? Theme.amber : Theme.secondaryText)
                    }
                    // `.enabled` and `.disabled` are distinct types, so this
                    // can't be a ternary inside one `.textSelection(...)`.
                    Group {
                        if isSelectable {
                            Text(segment.text).textSelection(.enabled)
                        } else {
                            Text(segment.text).textSelection(.disabled)
                        }
                    }
                    .font(.system(size: textSize))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
