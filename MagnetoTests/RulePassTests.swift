import Testing

/// Every case here comes from a dictation that came out wrong once. The rules run in a
/// fixed order and each one can undo the previous one's work, so the expected strings
/// are written whole rather than asserted piecewise.
@Suite("RulePass")
struct RulePassTests {
    private func clean(
        _ raw: String,
        vocabulary: [String] = [],
        typography: Bool = false
    ) -> String {
        RulePass.clean(raw, customWords: vocabulary, frenchTypography: typography)
    }

    @Test("a pause at the very end becomes a full stop")
    func trailingPause() {
        #expect(clean("bonjour tout le monde...") == "Bonjour tout le monde.")
        #expect(clean("attends\u{2026}") == "Attends.")
    }

    @Test("a pause before a new clause becomes a comma")
    func pauseBeforeNewClause() {
        #expect(clean("on va déployer... donc c'est bon") == "On va déployer, donc c'est bon")
    }

    @Test("a pause after a word that cannot end a clause only rejoins")
    func pauseAfterDanglingWord() {
        #expect(clean("je vais... le faire") == "Je vais le faire")
    }

    @Test("two pauses in a row keep the words around them apart")
    func consecutivePauses() {
        #expect(clean("je vais... euh... le faire") == "Je vais euh le faire")
        #expect(clean("du coup... voilà... on y va") == "Du coup, voilà on y va")
        #expect(clean("bon... alors... on y va") == "Bon, alors on y va")
    }

    @Test("a pause opening the text is simply removed")
    func leadingPause() {
        #expect(clean("... bonjour tout le monde") == "Bonjour tout le monde")
    }

    @Test("a pause right after punctuation is dropped")
    func pauseAfterPunctuation() {
        #expect(clean("bonjour,... ça va") == "Bonjour, ça va")
    }

    @Test("the vocabulary decides the casing of the word it reopens on")
    func vocabularyOwnsCasing() {
        #expect(clean("déployer sur... DV1", vocabulary: ["dv1"]) == "Déployer sur dv1")
    }

    @Test("French typography is the only thing the toggle changes")
    func frenchTypography() {
        #expect(clean("ça va ?", typography: true) == "Ça va\u{202F}?")
        #expect(clean("ça va ?", typography: false) == "Ça va?")
        #expect(clean("écoute : c'est fini", typography: true) == "Écoute\u{202F}: c'est fini")
    }

    @Test("a URL keeps its punctuation, typography included")
    func urlSurvives() {
        let dictated = "va voir https://example.com/page?id=42 stp"
        #expect(clean(dictated, typography: true) == "Va voir https://example.com/page?id=42 stp")
    }

    @Test("an e-mail address is left alone")
    func emailSurvives() {
        #expect(clean("écris à jean.dupont@example.com stp") == "Écris à jean.dupont@example.com stp")
    }

    @Test("curly quotes and guillemets come back as the ones on the keyboard")
    func quotesNormalized() {
        #expect(clean("il a dit « bonjour »") == "Il a dit \"bonjour\"")
        #expect(RulePass.normalizeQuotes("« test »") == "\"test\"")
        #expect(RulePass.normalizeQuotes("\u{201C}test\u{201D}") == "\"test\"")
    }

    @Test("spacing around punctuation is repaired in both directions")
    func punctuationSpacing() {
        #expect(clean("bonjour , ça va") == "Bonjour, ça va")
        #expect(clean("bonjour,ça va") == "Bonjour, ça va")
        #expect(clean("bonjour , , ça va") == "Bonjour, ça va")
    }

    @Test("a sentence that follows a full stop is capitalised")
    func capitalisation() {
        #expect(clean("c'est fini. on recommence") == "C'est fini. On recommence")
    }

    @Test("a leading comma from a clipped first word is removed")
    func leadingComma() {
        #expect(clean(", bonjour") == "Bonjour")
    }

    @Test("nothing but whitespace stays nothing")
    func emptyInput() {
        #expect(clean("   ").isEmpty)
    }
}
