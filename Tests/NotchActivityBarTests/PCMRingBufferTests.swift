import Testing
@testable import NotchActivityBar

@Suite("PCM ring buffer")
struct PCMRingBufferTests {
    @Test
    func zeroPaddingOnUnderflow() {
        let ring = PCMRingBuffer(maxSamples: 4)
        ring.append([1, 2])
        let drained = ring.drain(count: 4)
        #expect(drained == [1, 2, 0, 0])
    }

    @Test
    func exactDrainOfFullyFilledBuffer() {
        let ring = PCMRingBuffer(maxSamples: 4)
        ring.append([1, 2, 3, 4])
        let drained = ring.drain(count: 4)
        #expect(drained == [1, 2, 3, 4])
    }

    @Test
    func wrapAroundOnOverflow() {
        let ring = PCMRingBuffer(maxSamples: 4)
        ring.append([1, 2, 3, 4])
        // Pushes 5, 6 in, evicting the oldest samples (1, 2).
        ring.append([5, 6])
        let drained = ring.drain(count: 4)
        #expect(drained == [3, 4, 5, 6])
    }

    @Test
    func drainRemovesSamples() {
        let ring = PCMRingBuffer(maxSamples: 4)
        ring.append([1, 2, 3, 4])
        _ = ring.drain(count: 2)
        let remaining = ring.drain(count: 4)
        #expect(remaining == [3, 4, 0, 0])
    }
}
