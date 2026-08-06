import Foundation

/// Thread-safe fixed-capacity ring buffer of Int16 PCM samples. Used to let two
/// independent audio sources (mic + system audio) feed a periodic mixer that
/// drains a fixed sample count from each and sums them without memory re-allocations.
final class PCMRingBuffer: @unchecked Sendable {
    private var buffer: [Int16]
    private var head = 0
    private var tail = 0
    private var availableCount = 0
    private let capacity: Int
    private let lock = NSLock()

    init(maxSamples: Int) {
        self.capacity = maxSamples
        self.buffer = [Int16](repeating: 0, count: maxSamples)
    }

    func append(_ newSamples: [Int16]) {
        guard !newSamples.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        for sample in newSamples {
            buffer[head] = sample
            head = (head + 1) % capacity
            if availableCount < capacity {
                availableCount += 1
            } else {
                tail = (tail + 1) % capacity
            }
        }
    }

    /// Removes and returns exactly `requestedCount` samples, zero-padding if fewer are available.
    func drain(count requestedCount: Int) -> [Int16] {
        lock.lock()
        defer { lock.unlock() }

        var result = [Int16](repeating: 0, count: requestedCount)
        let availableToDrain = min(availableCount, requestedCount)

        for i in 0..<availableToDrain {
            result[i] = buffer[tail]
            tail = (tail + 1) % capacity
        }
        availableCount -= availableToDrain

        return result
    }
}

