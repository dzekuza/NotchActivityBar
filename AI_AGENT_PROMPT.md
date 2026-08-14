// Sources/NotchActivityBar/MeetingAudioCapture.swift

import Foundation
import AVFoundation
import os

@MainActor
final class MeetingAudioCapture {

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchActivityBar", category: "app")

    private var systemConverter: AVAudioConverter?
    private let mixQueue = DispatchQueue(label: "com.rysardgvozdovic.NotchActivityBar.mix")
    private var mixSource: DispatchSourceTimer?
    private var mixBuffer: [Int16] = []

    private var systemRing: PCMRingBuffer
    private var micRing: PCMRingBuffer

    private var outputFormat: AVAudioFormat
    private let mixIntervalSeconds: TimeInterval = 0.05

    var onPCMChunk: ((Data) -> Void)?

    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
        self.systemRing = PCMRingBuffer(maxSamples: Int(outputFormat.sampleRate * 10)) // 10s buffer
        self.micRing = PCMRingBuffer(maxSamples: Int(outputFormat.sampleRate * 10))
    }

    func startSystemAudioCapture() {
        let ring = systemRing
        let targetFormat = outputFormat
        let output = SystemAudioStreamOutput { [weak self] pcmBuffer in
            guard let self else { return }
            if self.systemConverter == nil || self.systemConverter?.inputFormat != pcmBuffer.format {
                self.systemConverter = AVAudioConverter(from: pcmBuffer.format, to: targetFormat)
            }
            guard let converter = self.systemConverter,
                  let samples = Self.convert(pcmBuffer, using: converter, targetFormat: targetFormat)
            else {
                self.log.error("System audio converter failed for format: \(pcmBuffer.format)")
                return
            }
            ring.append(samples)
        }
        output.start()
        log.info("System audio capture started")
    }

    private func startMixTimer() {
        let samplesPerTick = Int(outputFormat.sampleRate * mixIntervalSeconds)
        let source = DispatchSource.makeTimerSource(queue: mixQueue)
        source.schedule(deadline: .now() + mixIntervalSeconds, repeating: mixIntervalSeconds)
        source.setEventHandler { [weak self] in
            self?.mixAndEmit(sampleCount: samplesPerTick)
        }
        source.resume()
        mixSource = source
        log.info("Mix timer started on mixQueue")
    }

    func stop() {
        mixSource?.cancel()
        mixSource = nil
        log.info("Mix timer stopped")
    }

    private func mixAndEmit(sampleCount: Int) {
        let mic = micRing.drain(count: sampleCount)
        let system = systemRing.drain(count: sampleCount)
        // Reuse mixBuffer to avoid allocation churn
        if mixBuffer.count != sampleCount {
            mixBuffer = [Int16](repeating: 0, count: sampleCount)
        }
        for i in 0..<sampleCount {
            let sum = Int32(mic[i]) + Int32(system[i])
            mixBuffer[i] = Int16(clamping: sum)
        }
        let data = mixBuffer.withUnsafeBufferPointer { Data(buffer: $0) }
        onPCMChunk?(data)
    }

    static func convert(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter, targetFormat: AVAudioFormat) -> [Int16]? {
        // Conversion implementation as exists
        // Note: unchanged method body assumed
        return nil // placeholder to represent existing implementation
    }
}
