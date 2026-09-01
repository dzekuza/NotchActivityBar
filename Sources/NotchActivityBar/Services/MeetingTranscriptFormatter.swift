import Foundation
import NaturalLanguage

/// Turns a flat run of recognized words into something readable: one block per
/// speaker turn, one sentence per line inside it.
///
/// The recognizers hand back a single unbroken string. Even with punctuation
/// enabled that reads as a wall of text, which is what made recorded meetings
/// hard to scan — so sentence segmentation and speaker grouping both happen
/// here, on the way to the UI and to disk.
enum MeetingTranscriptFormatter {
    /// Groups timed words into speaker turns. Consecutive words sharing a
    /// speaker merge into one block; a word the timeline couldn't attribute
    /// inherits the turn in progress rather than starting an "unknown" block,
    /// since a brief overlap mid-sentence is crosstalk, not a speaker change.
    @MainActor
    static func segments(from words: [TimedTranscriptWord], timeline: SpeakerTimeline) -> [TranscriptSegment] {
        guard !words.isEmpty else { return [] }

        var blocks: [(speaker: MeetingSpeaker?, words: [String])] = []
        var runningSpeaker: MeetingSpeaker?

        for word in words {
            let attributed = timeline.dominantSpeaker(from: word.startedAt, to: word.endedAt) ?? runningSpeaker
            if let attributed { runningSpeaker = attributed }

            if let last = blocks.last, last.speaker == attributed {
                blocks[blocks.count - 1].words.append(word.text)
            } else {
                blocks.append((speaker: attributed, words: [word.text]))
            }
        }

        return blocks.enumerated().map { index, block in
            TranscriptSegment(
                index: index,
                speaker: block.speaker,
                text: breakIntoSentences(block.words.joined(separator: " "))
            )
        }
    }

    /// Fallback for engines that give no timing (Gemini Live): no speaker
    /// labels, but the text still gets sentence line breaks.
    static func unattributedSegments(from transcript: String) -> [TranscriptSegment] {
        let text = breakIntoSentences(transcript)
        guard !text.isEmpty else { return [] }
        return [TranscriptSegment(index: 0, speaker: nil, text: text)]
    }

    /// One sentence per line. Uses `NLTokenizer` rather than splitting on `.`
    /// so abbreviations and decimals don't get torn in half.
    static func breakIntoSentences(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let sentence = trimmed[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            return true
        }
        return sentences.isEmpty ? trimmed : sentences.joined(separator: "\n")
    }

    /// Flattens speaker blocks into the plain text that gets persisted, copied,
    /// searched, and sent for summarization.
    static func plainText(from segments: [TranscriptSegment]) -> String {
        segments.map { segment in
            guard let speaker = segment.speaker else { return segment.text }
            return "\(speaker.label):\n\(segment.text)"
        }
        .joined(separator: "\n\n")
    }
}
