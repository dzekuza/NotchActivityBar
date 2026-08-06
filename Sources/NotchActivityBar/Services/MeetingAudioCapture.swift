@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Captures both sides of a call: system audio output (what you hear — the other
/// participant, via ScreenCaptureKit's audio-only capture) and the microphone
/// (what you say, via AVAudioEngine), mixes them into one 16kHz mono Int16 PCM
/// stream, and hands off fixed-size chunks for streaming transcription.
@MainActor
final class MeetingAudioCapture: NSObject {
    enum CaptureError: Error {
        case noDisplay
    }

    var onPCMChunk: ((Data) -> Void)?

    /// Invoked when the system ends the capture externally (e.g. the user
    /// clicks "Stop Sharing" in the menu bar screen-capture indicator), so the
    /// owner can tear down the rest of the recording session.
    var onStreamStopped: (() -> Void)?

    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
    private let mixIntervalSeconds: Double = 0.1

    private let audioEngine = AVAudioEngine()
    private var micConverter: AVAudioConverter?
    private var stream: SCStream?
    private var streamOutput: SystemAudioStreamOutput?

    private let micRing = PCMRingBuffer(maxSamples: 16_000 * 5)
    private let systemRing = PCMRingBuffer(maxSamples: 16_000 * 5)
    private var mixTimer: Timer?

    func start(inputDeviceID: AudioDeviceID? = nil) async throws {
        try startMicCapture(inputDeviceID: inputDeviceID)
        do {
            try await startSystemAudioCapture()
        } catch {
            NSLog("MeetingAudioCapture: system audio capture unavailable (\(error.localizedDescription)) — proceeding with mic capture only.")
        }
        startMixTimer()
    }

    func stop() {
        mixTimer?.invalidate()
        mixTimer = nil

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        let stream = stream
        self.stream = nil
        streamOutput = nil
        Task { try? await stream?.stopCapture() }
    }

    // MARK: - Microphone

    private func startMicCapture(inputDeviceID: AudioDeviceID?) throws {
        let input = audioEngine.inputNode
        if let deviceID = inputDeviceID, let unit = input.audioUnit {
            var devID = deviceID
            AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &devID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return }
        micConverter = converter

        // The tap fires on a realtime audio queue. The closure must be @Sendable
        // so it doesn't inherit this class's MainActor isolation — an isolated
        // closure traps the runtime's executor check when called off-main.
        let ring = micRing
        let targetFormat = outputFormat
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { @Sendable buffer, _ in
            guard let samples = Self.convert(buffer, using: converter, targetFormat: targetFormat) else { return }
            ring.append(samples)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    // MARK: - System audio

    private func startSystemAudioCapture() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw CaptureError.noDisplay }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        // Keep the (unused) video side of the stream minimal — SCStream requires
        // a video configuration even for audio-only capture.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let ring = systemRing
        let targetFormat = outputFormat
        let output = SystemAudioStreamOutput { pcmBuffer in
            guard let converter = AVAudioConverter(from: pcmBuffer.format, to: targetFormat),
                  let samples = Self.convert(pcmBuffer, using: converter, targetFormat: targetFormat)
            else { return }
            ring.append(samples)
        }
        streamOutput = output

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.rysardgvozdovic.NotchActivityBar.systemaudio"))
        try await stream.startCapture()
        self.stream = stream
    }

    // MARK: - Mixing

    private func startMixTimer() {
        let samplesPerTick = Int(outputFormat.sampleRate * mixIntervalSeconds)
        mixTimer = Timer.scheduledTimer(withTimeInterval: mixIntervalSeconds, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.mixAndEmit(sampleCount: samplesPerTick)
            }
        }
    }

    private func mixAndEmit(sampleCount: Int) {
        let mic = micRing.drain(count: sampleCount)
        let system = systemRing.drain(count: sampleCount)
        var mixed = [Int16](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let sum = Int32(mic[i]) + Int32(system[i])
            mixed[i] = Int16(clamping: sum)
        }
        let data = mixed.withUnsafeBufferPointer { Data(buffer: $0) }
        onPCMChunk?(data)
    }

    // MARK: - Conversion helpers

    private nonisolated static func convert(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter, targetFormat: AVAudioFormat) -> [Int16]? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }

        final class ProvidedFlag: @unchecked Sendable { var value = false }
        let provided = ProvidedFlag()
        var conversionError: NSError?
        let status = converter.convert(to: outBuffer, error: &conversionError) { _, inputStatus in
            if provided.value {
                inputStatus.pointee = .noDataNow
                return nil
            }
            provided.value = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, conversionError == nil, outBuffer.frameLength > 0,
              let channelData = outBuffer.int16ChannelData
        else { return nil }

        let frameCount = Int(outBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
    }
}

extension MeetingAudioCapture: SCStreamDelegate {
    /// Fires when the capture ends outside our control — most commonly the user
    /// clicking "Stop Sharing" in the system's screen-capture menu bar indicator.
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let stoppedStreamID = ObjectIdentifier(stream)
        Task { @MainActor in
            guard let current = self.stream, ObjectIdentifier(current) == stoppedStreamID else { return }
            self.stream = nil
            self.onStreamStopped?()
        }
    }
}

/// Bridges ScreenCaptureKit's CMSampleBuffer audio callback onto the main actor.
/// The callback fires on the stream's sample-handler queue, so `onBuffer` must
/// be @Sendable (a MainActor-isolated closure would trap when called there).
private final class SystemAudioStreamOutput: NSObject, SCStreamOutput {
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void

    init(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        self.onBuffer = onBuffer
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let pcmBuffer = sampleBuffer.asPCMBuffer() else { return }
        onBuffer(pcmBuffer)
    }
}

private extension CMSampleBuffer {
    func asPCMBuffer() -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(self),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let format = AVAudioFormat(streamDescription: asbd)
        else { return nil }

        let frameCount = CMSampleBufferGetNumSamples(self)
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            self,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let sourceList = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        let destinationList = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for index in 0..<min(sourceList.count, destinationList.count) {
            guard let sourceData = sourceList[index].mData else { continue }
            memcpy(destinationList[index].mData, sourceData, Int(sourceList[index].mDataByteSize))
        }
        return buffer
    }
}
