import CoreAudio
import Foundation

/// The default input device, reduced to the two things a dictation needs to know: how it
/// is attached, which decides which capture path runs, and a label for the journal. The
/// name is deliberately left out of both: the transport is what explains a failure, and a
/// device name can carry someone's first name into a report meant to be pasted.
struct InputDevice {
    let id: AudioDeviceID?
    let transport: String
    let isBuiltIn: Bool

    /// An unreadable device is treated as external: the resilient path costs a little more
    /// code on a machine that would have been fine without it, where the reverse would put
    /// the fragile path in front of hardware nobody vouched for.
    static var current: InputDevice {
        guard let device = defaultInput, let transport = transportType(of: device) else {
            return InputDevice(id: nil, transport: "indéterminée", isBuiltIn: false)
        }
        return InputDevice(
            id: device,
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
