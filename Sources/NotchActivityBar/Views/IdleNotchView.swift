import SwiftUI

/// The language chooser shown under the notch as a recording begins.
struct LanguagePrompt: Equatable {
    var languages: [MeetingLanguage]
    var selectedCode: String
    var engineSupportsSelection: Bool

    static func == (lhs: LanguagePrompt, rhs: LanguagePrompt) -> Bool {
        lhs.selectedCode == rhs.selectedCode
            && lhs.engineSupportsSelection == rhs.engineSupportsSelection
            && lhs.languages == rhs.languages
    }
}

struct IdleNotchView: View {
    var size: CGSize = CGSize(width: Theme.idleWidth, height: Theme.idleHeight)

    /// Width of the notch shape itself, which stays put while `size.width`
    /// grows to fit a wider accessory pill beneath it.
    var notchWidth: CGFloat = Theme.idleWidth
    var pillHeight: CGFloat = Theme.idleHeight
    var cornerRadius: CGFloat = 14
    var toast: NotchToast?
    var isRecording: Bool = false
    var liveTranscript: String = ""
    var onStopRecording: () -> Void = {}
    var languagePrompt: LanguagePrompt?
    var onSelectLanguage: (String) -> Void = { _ in }
    var onConfirmLanguage: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(topCornerRadius: Theme.notchTopCornerRadius, bottomCornerRadius: cornerRadius)
                .fill(Theme.panelBackground)
                .frame(width: notchWidth, height: pillHeight)
                .overlay(alignment: .center) {
                    Circle()
                        .fill(Theme.amber)
                        .frame(width: 6, height: 6)
                        .shadow(color: Theme.amber.opacity(0.6), radius: 4)
                        .opacity(toast == nil && !isRecording ? 1 : 0)
                }

            // The language prompt outranks the recording banner: it is only up
            // for the opening seconds, and it is the one thing the user may
            // need to act on before the meeting is lost to the wrong language.
            if toast == nil, let languagePrompt {
                languagePill(languagePrompt)
                    .padding(.top, pillHeight + Theme.toastGap)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if toast == nil, isRecording {
                recordingPill
                    .padding(.top, pillHeight + Theme.toastGap)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let toast {
                toastPill(toast)
                    .padding(.top, pillHeight + Theme.toastGap)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: toast)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isRecording)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: languagePrompt)
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private func toastPill(_ toast: NotchToast) -> some View {
        HStack(spacing: 6) {
            Image(systemName: toast.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.amber)
            Text(toast.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.toastPillHeight)
        .background(Capsule().fill(Theme.panelBackground))
        .frame(width: size.width, alignment: .center)
    }

    private func languagePill(_ prompt: LanguagePrompt) -> some View {
        HStack(spacing: 8) {
            PulsingRecordDot()
            Text("Language")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            Menu {
                ForEach(prompt.languages) { language in
                    Button(language.displayName) { onSelectLanguage(language.code) }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(MeetingLanguageCatalog.displayName(for: prompt.selectedCode))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.28)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            if !prompt.engineSupportsSelection {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .help("Apple Speech can't transcribe this language — switch to Gemini Live in Settings.")
            }

            Spacer(minLength: 0)

            Button(action: onConfirmLanguage) {
                Text("OK")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.28)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(width: Theme.languagePromptWidth, height: Theme.languagePillHeight)
        .background(SiriGradientView().clipShape(Capsule()))
        .frame(width: size.width, alignment: .center)
    }

    private var recordingPill: some View {
        HStack(spacing: 8) {
            PulsingRecordDot()
            Text(liveTranscript.isEmpty ? "Recording…" : liveTranscript)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .lineLimit(1)
                .frame(maxWidth: 110, alignment: .leading)

            Button(action: onStopRecording) {
                Text("Stop")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.28)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.recordingPillHeight)
        .background(SiriGradientView().clipShape(Capsule()))
        .frame(width: size.width, alignment: .center)
    }
}

/// A continuously flowing, Apple-Intelligence-style multicolor gradient used
/// as the recording extension's background. Two back-to-back copies of the
/// same color sequence are translated by exactly one tile width per loop, so
/// the wraparound is seamless.
private struct SiriGradientView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrolled = false

    private let baseColors: [Color] = [
        Color(red: 0.36, green: 0.34, blue: 1.0),
        Color(red: 0.68, green: 0.32, blue: 1.0),
        Color(red: 1.0, green: 0.36, blue: 0.66),
        Color(red: 1.0, green: 0.56, blue: 0.26)
    ]

    var body: some View {
        GeometryReader { proxy in
            let tileWidth = max(proxy.size.width, 1)
            LinearGradient(colors: baseColors + baseColors, startPoint: .leading, endPoint: .trailing)
                .frame(width: tileWidth * 2, height: proxy.size.height)
                .offset(x: scrolled ? -tileWidth : 0)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                        scrolled = true
                    }
                }
        }
        .clipped()
    }
}

private struct PulsingRecordDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(Theme.danger)
            .frame(width: 7, height: 7)
            .shadow(color: Theme.danger.opacity(0.7), radius: 3)
            .opacity(dimmed ? 0.35 : 1)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: dimmed
            )
            .onAppear { dimmed = true }
    }
}
