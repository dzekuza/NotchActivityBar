import AudioToolbox
import CoreAudio
import Foundation
import Observation

struct AudioInputDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let name: String
}

@MainActor
@Observable
final class AudioDeviceManager {
    static let shared = AudioDeviceManager()

    private(set) var availableDevices: [AudioInputDevice] = []
    var selectedDeviceID: AudioDeviceID? {
        didSet {
            if let id = selectedDeviceID {
                UserDefaults.standard.set(Int(id), forKey: userDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }
        }
    }

    private let userDefaultsKey = "NotchActivityBar_SelectedInputDeviceID"

    init() {
        if let savedID = UserDefaults.standard.object(forKey: userDefaultsKey) as? Int {
            self.selectedDeviceID = AudioDeviceID(savedID)
        }
        refreshDevices()
    }

    func refreshDevices() {
        let devices = Self.fetchAvailableInputDevices()
        self.availableDevices = devices

        if let selected = selectedDeviceID, !devices.contains(where: { $0.id == selected }) {
            self.selectedDeviceID = nil
        }
    }

    static func fetchAvailableInputDevices() -> [AudioInputDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize) == noErr,
              dataSize > 0
        else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs) == noErr
        else { return [] }

        var inputDevices: [AudioInputDevice] = []
        for deviceID in deviceIDs {
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize) == noErr, streamSize > 0 else { continue }

            let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(streamSize))
            defer { bufferListPtr.deallocate() }
            guard AudioObjectGetPropertyData(deviceID, &streamAddress, 0, nil, &streamSize, bufferListPtr) == noErr else { continue }

            let buffers = UnsafeMutableAudioBufferListPointer(bufferListPtr)
            var channelCount = 0
            for buffer in buffers {
                channelCount += Int(buffer.mNumberChannels)
            }
            guard channelCount > 0 else { continue }

            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            let status = withUnsafeMutablePointer(to: &name) { ptr in
                AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, ptr)
            }
            let deviceName = status == noErr ? (name as String) : "Audio Device \(deviceID)"
            inputDevices.append(AudioInputDevice(id: deviceID, name: deviceName))
        }
        return inputDevices
    }
}
