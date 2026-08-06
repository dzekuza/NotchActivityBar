import Foundation

/// Thread-safe fixed-capacity buffer of Int16 PCM samples. Used to let two
/// independent audio sources (mic + system audio) feed a periodic mixer that
/// drains a fixed sample count from each and sums them.
final class PCMRingBuffer: @unchecked Sendable {
    private var samples: [Int16] = []
    private let lock = NSLock()
    private let maxSamples: Int

    init(maxSamples: Int) {
        self.maxSamples = maxSamples
    }

    func append(_ newSamples: [Int16]) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(contentsOf: newSamples)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    /// Removes and returns exactly `count` samples, zero-padding if fewer are available.
    func drain(count: Int) -> [Int16] {
        lock.lock()
        defer { lock.unlock() }
        if samples.count >= count {
            let chunk = Array(samples[0..<count])
            samples.removeFirst(count)
            return chunk
        }
        var chunk = samples
        samples.removeAll()
        chunk.append(contentsOf: [Int16](repeating: 0, count: count - chunk.count))
        return chunk
    }
}
