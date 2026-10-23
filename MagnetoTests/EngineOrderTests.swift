import Testing

/// The chosen engine must be the one that answers, and an engine without a key must not
/// cost a failed request before the next one is tried.
@Suite("Ordre des moteurs")
struct EngineOrderTests {
    @Test("The chosen engine goes first")
    func chosenFirst() {
        #expect(Engine.order(primary: .elevenLabs, available: [.mistral, .elevenLabs]) == [.elevenLabs, .mistral])
        #expect(Engine.order(primary: .mistral, available: [.mistral, .elevenLabs]) == [.mistral, .elevenLabs])
    }

    @Test("An engine without a key is skipped")
    func missingKeySkipped() {
        #expect(Engine.order(primary: .mistral, available: [.elevenLabs]) == [.elevenLabs])
        #expect(Engine.order(primary: .elevenLabs, available: []).isEmpty)
    }
}

/// Each rule of the race, fed the events in the orders they can arrive in.
@Suite("Course entre les moteurs")
struct RaceTests {
    @Test("Scribe in time wins, even when Voxtral answered first")
    func preferredInTime() {
        var race = Race()
        race.fallback = .text("voxtral")
        #expect(race.verdict == .wait)
        race.preferred = .text("scribe")
        #expect(race.verdict == .preferred)
    }

    @Test("Past the deadline, Voxtral's text is taken as soon as it is there")
    func fallbackAfterDeadline() {
        var race = Race()
        race.deadlinePassed = true
        #expect(race.verdict == .wait)
        race.fallback = .text("voxtral")
        #expect(race.verdict == .fallback)
    }

    @Test("Past the deadline, Scribe still wins if it beats Voxtral")
    func preferredAfterDeadline() {
        var race = Race()
        race.deadlinePassed = true
        race.preferred = .text("scribe")
        #expect(race.verdict == .preferred)
    }

    @Test("A failed Scribe hands over to Voxtral without waiting for the deadline")
    func preferredFails() {
        var race = Race()
        race.preferred = .failed("quota")
        #expect(race.verdict == .wait)
        race.fallback = .text("voxtral")
        #expect(race.verdict == .fallback)
    }

    @Test("A failed Voxtral leaves Scribe all the time it needs")
    func fallbackFails() {
        var race = Race()
        race.fallback = .failed("clé")
        race.deadlinePassed = true
        #expect(race.verdict == .wait)
        race.preferred = .text("scribe")
        #expect(race.verdict == .preferred)
    }

    @Test("A long recording gets no deadline, a short one keeps it")
    func deadlineFollowsLength() {
        #expect(Race.deadline(forAudio: 10) == Race.deadline)
        #expect(Race.deadline(forAudio: Race.longAudio) == Race.deadline)
        #expect(Race.deadline(forAudio: Race.longAudio + 1) == .zero)
    }

    @Test("Both failed ends the race")
    func bothFail() {
        var race = Race()
        race.preferred = .failed("a")
        race.fallback = .failed("b")
        #expect(race.verdict == .bothFailed)
    }
}
