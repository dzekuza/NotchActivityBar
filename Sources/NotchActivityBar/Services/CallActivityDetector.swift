import CoreAudio
import Foundation
import Observation

/// Best-effort signal that a call/meeting is likely active: the system's
/// default input device reports it's "running somewhere", i.e. some process
/// (WhatsApp, a browser tab running Meet, Zoom, etc.) has an active mic tap.
/// There is no public API to know *which* app or *why*, so this can false-positive
/// on anything that touches the mic (dictation, voice memos, other recorders).
@MainActor
@Observable
final class CallActivityDetector {
    private(set) var isCallLikelyActive = false

    var onChange: ((Bool) -> Void)?

    private var timer: Timer?
    private let pollInterval: TimeInterval = 2.0

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let active = Self.isDefaultInputRunningSomewhere()
        guard active != isCallLikelyActive else { return }
        isCallLikelyActive = active
        onChange?(active)
    }

    private static func isDefaultInputRunningSomewhere() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &size, &deviceID) == noErr,
              deviceID != 0
        else { return false }

        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &runningAddress) else { return false }

        var isRunning: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &runningAddress, 0, nil, &runningSize, &isRunning) == noErr else { return false }
        return isRunning != 0
    }
}
