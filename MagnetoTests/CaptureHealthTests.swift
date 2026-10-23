import Testing

/// A Bluetooth stream reports no error whether it works or not, so these five verdicts are
/// all that stands between a dead link and a dictation that captured nothing.
@Suite("CaptureHealth")
struct CaptureHealthTests {
    @Test("digital silence early on is only a link still switching")
    func silenceEarlyIsStarting() {
        #expect(CaptureHealth(loudestSignal: 0, idleMilliseconds: nil, mutedMilliseconds: nil, elapsedMilliseconds: 600) == .starting)
        #expect(CaptureHealth(loudestSignal: 0, idleMilliseconds: 80, mutedMilliseconds: nil, elapsedMilliseconds: 600) == .starting)
    }

    @Test("digital silence past the grace period is a stream that never woke up")
    func silenceLateIsDead() {
        #expect(CaptureHealth(loudestSignal: 0, idleMilliseconds: nil, mutedMilliseconds: nil, elapsedMilliseconds: 1_500) == .silent)
        #expect(CaptureHealth(loudestSignal: 0, idleMilliseconds: 120, mutedMilliseconds: nil, elapsedMilliseconds: 4_000) == .silent)
    }

    @Test("a room's noise counts as sound, however faint")
    func faintNoiseIsLive() {
        #expect(CaptureHealth(loudestSignal: 0.0005, idleMilliseconds: 40, mutedMilliseconds: nil, elapsedMilliseconds: 120) == .live)
    }

    @Test("a stream that carried sound and stopped is a stall, not a silence")
    func stoppedStreamIsStalled() {
        #expect(CaptureHealth(loudestSignal: 0.2, idleMilliseconds: 800, mutedMilliseconds: nil, elapsedMilliseconds: 5_000) == .stalled)
    }

    @Test("someone pausing mid-dictation is not a stall")
    func quietSpeakerStaysLive() {
        #expect(CaptureHealth(loudestSignal: 0.2, idleMilliseconds: 100, mutedMilliseconds: nil, elapsedMilliseconds: 9_000) == .live)
    }

    @Test("a stream that carried sound and now delivers only zeros has lost its microphone")
    func zerosAfterSoundAreMuted() {
        #expect(CaptureHealth(loudestSignal: 0.2, idleMilliseconds: 40, mutedMilliseconds: 1_000, elapsedMilliseconds: 5_000) == .muted)
    }

    @Test("a short run of zeros is a headset's noise gate, not a lost microphone")
    func briefZerosStayLive() {
        #expect(CaptureHealth(loudestSignal: 0.2, idleMilliseconds: 40, mutedMilliseconds: 400, elapsedMilliseconds: 5_000) == .live)
    }
}
