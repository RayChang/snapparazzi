import Foundation
import CoreAudio

// Test helper for simulating a microphone that disappears mid-recording:
//   recording-audio-device list                       print "in|out UID name" for every device
//   recording-audio-device default-input              print the default input device UID
//   recording-audio-device create-aggregate UID        create a public aggregate device that
//                                                      wraps input UID; print the new UID
//   recording-audio-device set-default-input UID       make UID the default input
//   recording-audio-device destroy UID                 destroy the aggregate device UID

private let system = AudioObjectID(kAudioObjectSystemObject)
private let testUID = "dev.snapparazzi.test-microphone"

private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                               mElement: kAudioObjectPropertyElementMain)
}

private func fail(_ message: String) -> Never {
    fputs("recording-audio-device: \(message)\n", stderr)
    exit(1)
}

private func defaultInput() -> AudioObjectID {
    var id = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var property = address(kAudioHardwarePropertyDefaultInputDevice)
    guard AudioObjectGetPropertyData(system, &property, 0, nil, &size, &id) == noErr, id != 0 else {
        fail("no default input device")
    }
    return id
}

private func uid(of device: AudioObjectID) -> String {
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var property = address(kAudioDevicePropertyDeviceUID)
    guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr,
          let value else { fail("cannot read device UID") }
    return value.takeRetainedValue() as String
}

private func device(for uid: String) -> AudioObjectID? {
    var id = AudioObjectID(0)
    var cfUID = uid as CFString
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var property = address(kAudioHardwarePropertyTranslateUIDToDevice)
    let status = withUnsafeMutablePointer(to: &cfUID) {
        AudioObjectGetPropertyData(system, &property, UInt32(MemoryLayout<CFString>.size), $0, &size, &id)
    }
    return status == noErr && id != 0 ? id : nil
}

private func name(of device: AudioObjectID) -> String {
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var property = address(kAudioObjectPropertyName)
    guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr, let value else { return "?" }
    return value.takeRetainedValue() as String
}

private func hasStreams(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
    var property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope,
                                              mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(0)
    return AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size) == noErr && size > 0
}

let arguments = CommandLine.arguments
switch (arguments.count, arguments.count > 1 ? arguments[1] : "") {
case (2, "list"):
    var property = address(kAudioHardwarePropertyDevices)
    var size = UInt32(0)
    AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size)
    var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(system, &property, 0, nil, &size, &devices)
    for device in devices {
        let direction = (hasStreams(device, scope: kAudioObjectPropertyScopeInput) ? "in" : "")
            + (hasStreams(device, scope: kAudioObjectPropertyScopeOutput) ? "out" : "")
        print("\(direction)\t\(uid(of: device))\t\(name(of: device))")
    }
case (2, "default-input"):
    print(uid(of: defaultInput()))
case (3, "create-aggregate"):
    let description: [String: Any] = [
        kAudioAggregateDeviceUIDKey: testUID,
        kAudioAggregateDeviceNameKey: "Snapparazzi Test Microphone",
        kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: arguments[2]]],
        kAudioAggregateDeviceMainSubDeviceKey: arguments[2],
        kAudioAggregateDeviceIsPrivateKey: 0
    ]
    var id = AudioObjectID(0)
    let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
    guard status == noErr else { fail("cannot create aggregate device (\(status))") }
    print(testUID)
case (3, "set-default-input"):
    guard var id = device(for: arguments[2]) else { fail("no device with UID \(arguments[2])") }
    var property = address(kAudioHardwarePropertyDefaultInputDevice)
    let status = AudioObjectSetPropertyData(system, &property, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &id)
    guard status == noErr else { fail("cannot set default input (\(status))") }
case (3, "destroy"):
    guard let id = device(for: arguments[2]) else { fail("no device with UID \(arguments[2])") }
    let status = AudioHardwareDestroyAggregateDevice(id)
    guard status == noErr else { fail("cannot destroy aggregate device (\(status))") }
default:
    fail("usage: default-input | create-aggregate UID | set-default-input UID | destroy UID")
}
