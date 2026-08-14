import AVFoundation
import CoreAudio
import CoreMediaIO
import Foundation
import Observation

/// Mutes the system's default microphone and takes exclusive ownership of every
/// camera the OS knows about, so no other app can read from them while engaged.
@MainActor
@Observable
final class PrivacyGuardController {
    private(set) var isMuted = false
    private(set) var cameraAccessDenied = false

    private var micMuteStrategy: MicMuteStrategy?
    private var hoggedCameraDeviceIDs: [CMIODeviceID] = []
    private var muteRequestToken = 0

    /// `applicationWillTerminate` never fires on a force-quit or crash, which
    /// would otherwise leave the mic hardware-muted/silenced system-wide with
    /// no obvious cause. We persist the mute strategy to disk while engaged so
    /// the *next* launch can detect an unclean shutdown and restore it.
    init() {
        Self.recoverFromUncleanShutdownIfNeeded()
    }

    func toggle() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        guard muted != isMuted else { return }
        muteRequestToken += 1
        let token = muteRequestToken
        isMuted = muted

        if muted {
            micMuteStrategy = Self.muteDefaultInputDevice()
            Self.persistPendingRestore(micMuteStrategy)

            // CMIO won't enumerate real camera devices for a process that hasn't
            // been granted Camera access, so hog-mode claims silently no-op until
            // TCC authorization is confirmed (prompting the user the first time).
            Task { @MainActor in
                let authorized = await Self.ensureCameraAuthorization()
                guard token == self.muteRequestToken else { return }
                self.cameraAccessDenied = !authorized
                guard authorized else { return }
                self.hoggedCameraDeviceIDs = Self.claimCameraDevices()
            }
        } else {
            if let micMuteStrategy {
                Self.restoreDefaultInputDevice(strategy: micMuteStrategy)
            }
            Self.releaseCameraDevices(hoggedCameraDeviceIDs)
            micMuteStrategy = nil
            hoggedCameraDeviceIDs = []
            Self.clearPendingRestore()
        }
    }

    // MARK: - Crash-safe mic restore

    private enum PendingRestoreKeys {
        static let kind = "PrivacyGuardPendingRestoreKind"
        static let deviceID = "PrivacyGuardPendingRestoreDeviceID"
        static let previousMute = "PrivacyGuardPendingRestorePreviousMute"
        static let previousVolume = "PrivacyGuardPendingRestorePreviousVolume"
    }

    private static func persistPendingRestore(_ strategy: MicMuteStrategy?) {
        let defaults = UserDefaults.standard
        guard let strategy else {
            clearPendingRestore()
            return
        }
        switch strategy {
        case .hardwareMute(let device, let previous):
            defaults.set("hardwareMute", forKey: PendingRestoreKeys.kind)
            defaults.set(Int(device), forKey: PendingRestoreKeys.deviceID)
            defaults.set(previous, forKey: PendingRestoreKeys.previousMute)
        case .volumeZero(let device, let previous):
            defaults.set("volumeZero", forKey: PendingRestoreKeys.kind)
            defaults.set(Int(device), forKey: PendingRestoreKeys.deviceID)
            defaults.set(Double(previous), forKey: PendingRestoreKeys.previousVolume)
        }
    }

    private static func clearPendingRestore() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: PendingRestoreKeys.kind)
        defaults.removeObject(forKey: PendingRestoreKeys.deviceID)
        defaults.removeObject(forKey: PendingRestoreKeys.previousMute)
        defaults.removeObject(forKey: PendingRestoreKeys.previousVolume)
    }

    /// Runs once at launch. If a mute strategy is still recorded, the previous
    /// run never cleanly called `setMuted(false)` (crash or force-quit) — restore
    /// the mic to its pre-guard state now. The recorded device ID may no longer
    /// be the default input (or may not exist at all, e.g. USB mic unplugged);
    /// in that case there's nothing meaningful left to restore, so just clear it.
    private static func recoverFromUncleanShutdownIfNeeded() {
        let defaults = UserDefaults.standard
        guard let kind = defaults.string(forKey: PendingRestoreKeys.kind) else { return }
        defer { clearPendingRestore() }

        let deviceID = AudioDeviceID(defaults.integer(forKey: PendingRestoreKeys.deviceID))
        guard deviceID != 0 else { return }

        switch kind {
        case "hardwareMute":
            let previous = defaults.bool(forKey: PendingRestoreKeys.previousMute)
            restoreDefaultInputDevice(strategy: .hardwareMute(device: deviceID, previous: previous))
        case "volumeZero":
            let previous = Float32(defaults.double(forKey: PendingRestoreKeys.previousVolume))
            restoreDefaultInputDevice(strategy: .volumeZero(device: deviceID, previous: previous))
        default:
            break
        }
        NSLog("PrivacyGuardController: restored mic after an unclean shutdown left it muted")
    }

    private static func ensureCameraAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await PermissionPrompt.around { await AVCaptureDevice.requestAccess(for: .video) }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Microphone (CoreAudio)

    private enum MicMuteStrategy {
        case hardwareMute(device: AudioDeviceID, previous: Bool)
        case volumeZero(device: AudioDeviceID, previous: Float32)
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    private static func muteDefaultInputDevice() -> MicMuteStrategy? {
        guard let deviceID = defaultInputDeviceID() else { return nil }

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &muteAddress) {
            var settable: DarwinBoolean = false
            AudioObjectIsPropertySettable(deviceID, &muteAddress, &settable)
            if settable.boolValue {
                var current: UInt32 = 0
                var size = UInt32(MemoryLayout<UInt32>.size)
                if AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &size, &current) == noErr {
                    var newValue: UInt32 = 1
                    if AudioObjectSetPropertyData(deviceID, &muteAddress, 0, nil, size, &newValue) == noErr {
                        return .hardwareMute(device: deviceID, previous: current != 0)
                    }
                }
            }
        }

        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &volumeAddress) else { return nil }
        var settable: DarwinBoolean = false
        AudioObjectIsPropertySettable(deviceID, &volumeAddress, &settable)
        guard settable.boolValue else { return nil }

        var current = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &size, &current) == noErr else { return nil }
        var zero = Float32(0)
        guard AudioObjectSetPropertyData(deviceID, &volumeAddress, 0, nil, size, &zero) == noErr else { return nil }
        return .volumeZero(device: deviceID, previous: current)
    }

    private static func restoreDefaultInputDevice(strategy: MicMuteStrategy) {
        switch strategy {
        case .hardwareMute(let deviceID, let previous):
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var value: UInt32 = previous ? 1 : 0
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        case .volumeZero(let deviceID, let previous):
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var value = previous
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
    }

    // MARK: - Camera (CoreMediaIO)

    private static func cameraDeviceIDs() -> [CMIODeviceID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &dataSize) == noErr,
              dataSize > 0
        else { return [] }

        let count = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
        var devices = [CMIODeviceID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        let status = devices.withUnsafeMutableBytes { buffer -> OSStatus in
            CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, dataSize, &dataUsed, buffer.baseAddress)
        }
        guard status == noErr else { return [] }
        return devices
    }

    private static func hogModeAddress() -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyHogMode),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    private static func claimCameraDevices() -> [CMIODeviceID] {
        var claimed: [CMIODeviceID] = []
        for deviceID in cameraDeviceIDs() {
            var address = hogModeAddress()
            guard CMIOObjectHasProperty(deviceID, &address) else { continue }
            var settable: DarwinBoolean = false
            CMIOObjectIsPropertySettable(deviceID, &address, &settable)
            guard settable.boolValue else { continue }

            var currentOwner: pid_t = -1
            let getSize = UInt32(MemoryLayout<pid_t>.size)
            var dataUsed: UInt32 = 0
            CMIOObjectGetPropertyData(deviceID, &address, 0, nil, getSize, &dataUsed, &currentOwner)
            guard currentOwner == -1 else { continue }

            var myPID = pid_t(ProcessInfo.processInfo.processIdentifier)
            let status = CMIOObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<pid_t>.size), &myPID)
            if status == noErr {
                claimed.append(deviceID)
            }
        }
        return claimed
    }

    private static func releaseCameraDevices(_ deviceIDs: [CMIODeviceID]) {
        for deviceID in deviceIDs {
            var address = hogModeAddress()
            var release: pid_t = -1
            CMIOObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<pid_t>.size), &release)
        }
    }
}
