import Foundation

/// Records which audio channel was carrying speech over time, so transcript
/// segments can be attributed to a speaker after the fact.
///
/// `MeetingAudioCapture` samples this every mix tick (100ms). Attribution is a
/// straight loudness comparison between the two channels, which is what makes
/// it robust to echo: when the far end is played through speakers it bleeds
/// back into the microphone, but always quieter than the system-audio original,
/// so the true source still wins.
@MainActor
final class SpeakerTimeline {
    private struct Sample {
        let at: Date
        let speaker: MeetingSpeaker?
    }

    /// Mean absolute amplitude (Int16 scale) below which a channel counts as
    /// silent rather than quiet speech. Room tone and mic self-noise sit well
    /// under this; speech sits far above it.
    private let silenceFloor: Double = 220

    /// How much louder one channel must be before it takes the turn. Keeps a
    /// steady bleed or a cough on the other channel from flipping the label
    /// mid-sentence.
    private let dominanceMargin: Double = 1.35

    private var samples: [Sample] = []

    func reset() {
        samples.removeAll()
    }

    func record(micLevel: Double, systemLevel: Double, at date: Date) {
        samples.append(Sample(at: date, speaker: Self.dominant(
            micLevel: micLevel,
            systemLevel: systemLevel,
            silenceFloor: silenceFloor,
            margin: dominanceMargin
        )))
    }

    private static func dominant(micLevel: Double, systemLevel: Double, silenceFloor: Double, margin: Double) -> MeetingSpeaker? {
        let micActive = micLevel > silenceFloor
        let systemActive = systemLevel > silenceFloor
        switch (micActive, systemActive) {
        case (false, false): return nil
        case (true, false): return .you
        case (false, true): return .other
        case (true, true):
            if micLevel > systemLevel * margin { return .you }
            if systemLevel > micLevel * margin { return .other }
            // Genuine crosstalk — neither side clearly owns the moment. Leave it
            // unattributed and let the surrounding samples decide the segment.
            return nil
        }
    }

    /// Whoever held the floor for most of `start..<end`. Ties and all-silent
    /// spans return nil, letting the caller fall back to the running speaker.
    func dominantSpeaker(from start: Date, to end: Date) -> MeetingSpeaker? {
        var youCount = 0
        var otherCount = 0
        for sample in samples where sample.at >= start && sample.at <= end {
            switch sample.speaker {
            case .you: youCount += 1
            case .other: otherCount += 1
            case nil: break
            }
        }
        if youCount > otherCount { return .you }
        if otherCount > youCount { return .other }
        return nil
    }
}
