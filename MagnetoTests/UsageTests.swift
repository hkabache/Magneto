import Testing

/// What the Consommation rows print, since a wrong figure there would go unnoticed.
@Suite("Consommation")
struct UsageTests {
    @Test("A few cents never read as free")
    func smallCosts() {
        #expect(Usage.dollars(0) == "0,00 $")
        #expect(Usage.dollars(0.004) == "< 0,01 $")
        #expect(Usage.dollars(0.1, exact: true) == "0,10 $")
        #expect(Usage.dollars(1.234) == "1,23 $")
    }

    @Test("Costs add up across engines, the audio is counted once")
    func totals() {
        var usage = Usage(dictations: 2, seconds: 120)
        usage.costs[Engine.elevenLabs.rawValue] = 0.03
        usage.costs[Engine.microsoft.rawValue] = 0.02
        #expect(usage.cost == 0.05)
        #expect(usage.summary == "2 dictées · 0,05 $")
        #expect(usage.detail == "2 min d'audio · Microsoft 0,02 $ · ElevenLabs 0,03 $")
    }

    @Test("An engine that cost nothing is left out of the detail")
    func idleEngineHidden() {
        let usage = Usage(dictations: 1, seconds: 30)
        #expect(usage.summary == "1 dictée · 0,00 $")
        #expect(usage.detail == "1 min d'audio")
    }
}
