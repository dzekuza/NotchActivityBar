import AppKit
import SwiftUI

/// Full transcript for one recorded meeting. The card only ever shows a
/// four-line preview, so this is the only place the text is actually readable.
/// Read-only — unlike `NoteDetailOverlay` there's nothing here to edit.
struct MeetingDetailOverlay: View {
    let session: MeetingSession
    let onDelete: () -> Void
    let onClose: () -> Void

    @State private var showCopiedConfirmation = false

    private var summary: String? {
        guard let summary = session.summary, !summary.isEmpty else { return nil }
        return summary
    }

    private var transcript: String {
        session.transcript.isEmpty ? "No transcript" : session.transcript
    }

    var body: some View {
        ZStack {
            Theme.modalScrim
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 0) {
                header
                body(for: session)
            }
            .frame(width: Theme.expandedWidth - 120)
            .background(Theme.panelBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.cardBorderHover, lineWidth: 1)
            }
        }
        .animation(.easeOut(duration: 0.15), value: showCopiedConfirmation)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.amber)
            Text(session.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            Text(session.durationLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.tertiaryText)

            Spacer(minLength: 8)

            if showCopiedConfirmation {
                Text("Copied")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .transition(.opacity)
            }
            Button(action: copyToClipboard) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.overlayButtonBackground))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy transcript")
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.overlayButtonBackground))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete meeting")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.overlayButtonBackground))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func body(for session: MeetingSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let summary {
                    section(title: "Summary", text: summary)
                }
                if let segments = session.segments, !segments.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if summary != nil {
                            Text("Transcript")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.tertiaryText)
                                .textCase(.uppercase)
                        }
                        TranscriptSegmentsView(segments: segments)
                    }
                } else {
                    // Recorded before speaker labels existed — no turns to show.
                    section(title: summary == nil ? nil : "Transcript", text: transcript)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxHeight: min(Theme.expandedMaxHeight - 80, 320))
    }

    private func section(title: String?, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
                    .textCase(.uppercase)
            }
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func copyToClipboard() {
        let text = summary.map { "\($0)\n\n\(transcript)" } ?? transcript
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        showCopiedConfirmation = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            showCopiedConfirmation = false
        }
    }
}
