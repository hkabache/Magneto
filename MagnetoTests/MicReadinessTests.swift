import Testing

/// The pill used to announce a live microphone the moment `record()` returned, which on
/// a Bluetooth headset is one to two seconds before the first sample exists.
@Suite("MicReadiness")
struct MicReadinessTests {
    @Test("the meter's floor value keeps the pill waiting")
    func floorKeepsWaiting() {
        #expect(MicReadiness(averagePower: -160, elapsedMilliseconds: 50) == .waiting)
    }

    @Test("a room's noise floor means the input is delivering")
    func noiseMeansDelivering() {
        #expect(MicReadiness(averagePower: -70, elapsedMilliseconds: 50) == .delivering)
        #expect(MicReadiness(averagePower: -12, elapsedMilliseconds: 1_800) == .delivering)
    }

    @Test("a device that never leaves the floor stops holding the pill back")
    func silentDeviceIsAssumedLive() {
        #expect(MicReadiness(averagePower: -160, elapsedMilliseconds: 2_500) == .assumed)
        #expect(MicReadiness(averagePower: -160, elapsedMilliseconds: 9_000) == .assumed)
    }
}
