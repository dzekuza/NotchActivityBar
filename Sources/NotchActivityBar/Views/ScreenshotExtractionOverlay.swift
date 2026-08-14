import AppKit
import SwiftUI

struct ScreenshotExtractionOverlay: View {
    let item: ScreenshotItem
    let state: ScreenshotExtractionState?
    let hasAPIKey: Bool
    let onClose: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Theme.modalScrim
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Text(item.appName)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Theme.overlayButtonBackground))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                content
                    .frame(maxHeight: min(Theme.expandedMaxHeight - 80, 320))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .frame(width: Theme.expandedWidth - 120)
            .background(Theme.panelBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.cardBorderHover, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !hasAPIKey {
            Text("Add a Gemini API key in Settings to extract text from screenshots.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            switch state {
            case nil, .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Extracting text…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            case .success(let text, let links):
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(text)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.primaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if !links.isEmpty {
                            Divider()
                            Text("Links")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.secondaryText)
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(links, id: \.self) { link in
                                    Button {
                                        NSWorkspace.shared.open(link)
                                    } label: {
                                        Text(link.absoluteString)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.primaryText)
                                            .underline()
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

            case .failure(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.danger)
                    Button("Retry", action: onRetry)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.inactiveTabBackground))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
