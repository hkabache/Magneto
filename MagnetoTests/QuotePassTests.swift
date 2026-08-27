import Testing

/// What is asserted here is mostly what the pass must *not* do. Every rule that once
/// touched spacing, casing or punctuation was repairing an engine that has left the chain,
/// and two of them damaged a text that arrived correct.
@Suite("QuotePass")
struct QuotePassTests {
    private func clean(_ raw: String) -> String {
        QuotePass.clean(raw)
    }

    @Test("guillemets and curly quotes come back as the ones on the keyboard")
    func quotesStraightened() {
        #expect(clean("il a dit « bonjour »") == "il a dit \"bonjour\"")
        #expect(clean("\u{201C}test\u{201D}") == "\"test\"")
        #expect(clean("« espace fine\u{202F}»") == "\"espace fine\"")
    }

    @Test("the casing the engine chose is left alone")
    func casingIsNotTouched() {
        // A few words dictated to patch the middle of an existing sentence must stay
        // lowercase: Scribe capitalises a sentence and not a fragment, on purpose.
        #expect(clean("ces dernières semaines") == "ces dernières semaines")
        #expect(clean("c'est fini. on recommence") == "c'est fini. on recommence")
    }

    @Test("punctuation is left exactly as dictated")
    func punctuationIsNotTouched() {
        #expect(clean("ça va ?") == "ça va ?")
        #expect(clean("écoute : c'est fini") == "écoute : c'est fini")
        #expect(clean("attends\u{2026}") == "attends\u{2026}")
        #expect(clean("bonjour,ça va") == "bonjour,ça va")
    }

    @Test("a URL and an e-mail address pass through untouched")
    func addressesSurvive() {
        #expect(clean("va voir https://example.com/page?id=42 stp") == "va voir https://example.com/page?id=42 stp")
        #expect(clean("écris à jean.dupont@example.com") == "écris à jean.dupont@example.com")
    }

    @Test("nothing but whitespace stays nothing")
    func blankStaysBlank() {
        #expect(clean("   ").isEmpty)
    }
}
