import CoreAudio
import Foundation

/// The default input device, reduced to what a dictation needs to know: how it is
/// attached, which decides which capture path runs, and which microphone it is, for the
/// journal. The transport alone said "Bluetooth" for a pair of AirPods 5 and AirPods Pro 2
/// alike, and a morning of degraded dictation could not be pinned on either. The name is
/// the one the system shows, so it can carry its owner's first name, which the README says.
struct InputDevice {
    let id: AudioDeviceID?
    let name: String
    let transport: String
    let isBuiltIn: Bool

    /// An unreadable device is treated as external: the resilient path costs a little more
    /// code on a machine that would have been fine without it, where the reverse would put
    /// the fragile path in front of hardware nobody vouched for.
    static var current: InputDevice {
        guard let device = defaultInput, let transport = transportType(of: device) else {
            return InputDevice(id: nil, name: "inconnu", transport: "indéterminée", isBuiltIn: false)
        }
        return InputDevice(
            id: device,
            name: name(of: device) ?? "sans nom",
            transport: label(for: transport),
            isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn
        )
    }

    private static var defaultInput: AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        guard status == noErr, device != AudioDeviceID(kAudioObjectUnknown) else { return nil }
        return device
    }

    private static func transportType(of device: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)
        return status == noErr ? transport : nil
    }

    private static func name(of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private static func label(for transport: UInt32) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "intégrée"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeVirtual: return "virtuelle"
        case kAudioDeviceTransportTypeAggregate: return "agrégée"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI: return "écran"
        case kAudioDeviceTransportTypeThunderbolt: return "Thunderbolt"
        default: return "autre"
        }
    }
}
