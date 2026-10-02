import AVFoundation
import CoreAudio
import Foundation

struct MicDevice {
    var id: AudioDeviceID
    var uid: String
    var name: String
}

func micDevices() -> [MicDevice] {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = Array(repeating: AudioDeviceID(0), count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
    return ids.compactMap { id in
        var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var streamSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
        let uid = audioString(id, kAudioDevicePropertyDeviceUID)
        guard !uid.isEmpty else { return nil }
        let name = audioString(id, kAudioObjectPropertyName)
        return MicDevice(id: id, uid: uid, name: name.isEmpty ? uid : name)
    }
}

func applyMic(uid: String, to engine: AVAudioEngine) {
    guard let device = micDevices().first(where: { $0.uid == uid }), let audioUnit = engine.inputNode.audioUnit else { return }
    var id = device.id
    AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
}

func audioString(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return "" }
    return value as String
}
