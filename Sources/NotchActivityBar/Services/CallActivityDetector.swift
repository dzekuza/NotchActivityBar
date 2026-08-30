import CoreAudio
import Foundation
import Observation

/// Best-effort signal that a call/meeting is likely active: some *other*
/// process (WhatsApp, a browser tab running Meet, Zoom, etc.) has an active
/// mic tap.
///
/// The "other" is the whole point. The obvious signal —
/// `kAudioDevicePropertyDeviceIsRunningSomewhere` on the default input device —
/// cannot say *who* is using the mic, and once we start recording we are
/// ourselves holding that device open via `MeetingAudioCapture`. Watching it
/// meant the falling edge never arrived and a recording never stopped itself.
/// So the primary check walks CoreAudio's per-process object list and skips our
/// own PID.
///
/// This still can't say *why* another process wants the mic, so it can
/// false-positive on any other app's mic use (dictation, Voice Memos, another
/// recorder).
@MainActor
@Observable
final class CallActivityDetector {
    private(set) var isCallLikelyActive = false

    /// False when CoreAudio wouldn't give us the per-process list and we fell
    /// back to the device-level property. In that mode the signal includes our
    /// own capture, so it can start a recording but never end one.
    private(set) var usesProcessLevelDetection = true

    var onChange: ((Bool) -> Void)?

    private var timer: Timer?
    private let pollInterval: TimeInterval = 2.0

    /// A call going quiet for one poll is usually not a call ending — clients
    /// release and re-acquire the mic tap on a device switch, on mute, or when
    /// renegotiating a stream. Require a few consecutive quiet polls (~6s)
    /// before believing it. The rising edge is not debounced: starting late
    /// loses the opening of the meeting.
    private let inactivePollsBeforeStop = 3
    private var consecutiveInactivePolls = 0

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
        let active = sampleMicrophoneActivity()

        if active {
            consecutiveInactivePolls = 0
            guard !isCallLikelyActive else { return }
            isCallLikelyActive = true
            onChange?(true)
            return
        }

        guard isCallLikelyActive else { return }
        consecutiveInactivePolls += 1
        guard consecutiveInactivePolls >= inactivePollsBeforeStop else { return }
        consecutiveInactivePolls = 0
        isCallLikelyActive = false
        onChange?(false)
    }

    private func sampleMicrophoneActivity() -> Bool {
        if let othersCapturing = Self.isOtherProcessCapturingInput() {
            usesProcessLevelDetection = true
            return othersCapturing
        }
        usesProcessLevelDetection = false
        return Self.isDefaultInputRunningSomewhere()
    }

    /// Whether any process *other than us* is running an input stream, or nil
    /// if CoreAudio wouldn't answer (in which case the caller falls back).
    private static func isOtherProcessCapturingInput() -> Bool? {
        var listAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectHasProperty(systemObject, &listAddress) else { return nil }

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &listAddress, 0, nil, &dataSize) == noErr,
              dataSize >= UInt32(MemoryLayout<AudioObjectID>.size)
        else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var processObjects = [AudioObjectID](repeating: 0, count: count)
        let status = processObjects.withUnsafeMutableBytes { buffer -> OSStatus in
            var size = dataSize
            return AudioObjectGetPropertyData(systemObject, &listAddress, 0, nil, &size, buffer.baseAddress!)
        }
        guard status == noErr else { return nil }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        for processObject in processObjects {
            // A process can disappear between the list snapshot and these
            // reads; a failed read just means "not this one".
            guard let pid = pid(of: processObject), pid != ownPID else { continue }
            if isRunningInput(processObject) { return true }
        }
        return false
    }

    private static func pid(of processObject: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(processObject, &address) else { return nil }

        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(processObject, &address, 0, nil, &size, &pid) == noErr else { return nil }
        return pid
    }

    private static func isRunningInput(_ processObject: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(processObject, &address) else { return false }

        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(processObject, &address, 0, nil, &size, &isRunning) == noErr else { return false }
        return isRunning != 0
    }

    /// Fallback for when the per-process list is unavailable. Cannot tell our
    /// own capture apart from anyone else's.
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
