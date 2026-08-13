import Foundation

/// macOS ignores a quick tap on Caps Lock: the key only toggles once it has been
/// held for about a tenth of a second, so anyone typing fast misses it. That delay
/// lives in the HID layer, where `hidutil` is the only supported way to override it.
///
/// The override belongs to the login session and is dropped at logout, so it is
/// re-applied at every launch instead of being written once.
enum CapsLockDelay {
    /// `hidutil` can set a property but never clear one, so switching the option off
    /// writes the stock delay back rather than removing the override.
    private static let systemDelayNanoseconds = 100_000_000

    static func apply(noDelay: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = [
            "property", "--set",
            "{\"CapsLockDelayOverride\":\(noDelay ? 0 : systemDelayNanoseconds)}",
        ]
        try? process.run()
    }
}
