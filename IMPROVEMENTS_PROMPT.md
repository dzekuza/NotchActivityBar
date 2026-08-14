//
//  MeetingAudioCapture.swift
//  NotchActivityBar
//
//  Created by Ryan Sardgvozdovic on 2023-06-17.
//

import Foundation
import AVFoundation
import ScreenCaptureKit
import Accelerate
import os

final class MeetingAudioCapture {
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchActivityBar", category: "audio")

    private let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private let mixIntervalSeconds = 0.01

    // Rings for mic and system audio data
    private let micRing = PCMRingBuffer(maxSamples: 44100 * 2) // 2 seconds buffer
    private let systemRing = PCMRingBuffer(maxSamples: 44100 * 2)

    // Cached converter for system audio format conversion
    private var systemConverter: AVAudioConverter?

    // Mixing buffer reused every tick
    private var mixBuffer: [Int16] = []

    // Mixing timer properties
    private let mixQueue = DispatchQueue(label: "com.rysardgvozdovic.NotchActivityBar.mix")
    private var mixSource: DispatchSourceTimer?

    // Callback with mixed PCM data (Int16 interleaved mono)
    var onPCMChunk: ((Data) -> Void)?

    func startSystemAudioCapture() {
        // Assuming systemAudioStreamOutput is created here
        let ring = systemRing
        let targetFormat = outputFormat
        let output = SystemAudioStreamOutput { [weak self] pcmBuffer in
            guard let self = self else { return }
            // Create or reuse a converter for the source -> target format
            if self.systemConverter == nil || self.systemConverter?.inputFormat != pcmBuffer.format {
                self.systemConverter = AVAudioConverter(from: pcmBuffer.format, to: targetFormat)
            }
            guard let converter = self.systemConverter,
                  let samples = Self.convert(pcmBuffer, using: converter, targetFormat: targetFormat)
            else {
                self.log.error("Failed to convert system audio buffer")
                return
            }
            ring.append(samples)
        }
        // start output etc.
    }

    private static func convert(_ buffer: AVAudioPCMBuffer,
                                using converter: AVAudioConverter,
                                targetFormat: AVAudioFormat) -> [Int16]? {
        // Conversion logic here; returning Int16 samples
        // For brevity, assuming implementation exists
        return nil
    }

    func startMixTimer() {
        let samplesPerTick = Int(outputFormat.sampleRate * mixIntervalSeconds)
        let source = DispatchSource.makeTimerSource(queue: mixQueue)
        source.schedule(deadline: .now() + mixIntervalSeconds, repeating: mixIntervalSeconds)
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.mixAndEmit(sampleCount: samplesPerTick)
        }
        source.resume()
        mixSource = source
        log.info("Mix timer started on mixQueue")
    }

    private func mixAndEmit(sampleCount: Int) {
        let mic = micRing.drain(count: sampleCount)
        let system = systemRing.drain(count: sampleCount)

        if mixBuffer.count != sampleCount {
            mixBuffer = [Int16](repeating: 0, count: sampleCount)
        }

        // Using Accelerate for vector addition
        var micFloat = mic.map { Float($0) }
        var sysFloat = system.map { Float($0) }
        var outFloat = [Float](repeating: 0, count: sampleCount)
        vDSP_vadd(&micFloat, 1, &sysFloat, 1, &outFloat, 1, vDSP_Length(sampleCount))

        for i in 0..<sampleCount {
            let clamped = min(max(Int(outFloat[i]), Int(Int16.min)), Int(Int16.max))
            mixBuffer[i] = Int16(clamped)
        }

        let data = mixBuffer.withUnsafeBufferPointer { Data(buffer: $0) }
        onPCMChunk?(data)
    }

    func stop() {
        mixSource?.cancel()
        mixSource = nil
        log.info("Mix timer stopped")
        // Other cleanup
    }
}
