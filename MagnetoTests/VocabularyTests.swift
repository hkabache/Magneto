import Testing

/// The two engines accept the vocabulary in incompatible shapes, and both reject the
/// whole request rather than the offending term when a rule is broken.
@Suite("Vocabulaire envoyé aux moteurs")
struct VocabularyTests {
    @Test("Scribe keyterms drop what the API refuses")
    func keytermsFiltering() {
        #expect(ElevenLabsClient.keyterms(from: ["Kube<r>netes"]) == ["Kubernetes"])
        #expect(ElevenLabsClient.keyterms(from: ["un deux trois quatre cinq"]) == ["un deux trois quatre cinq"])
        #expect(ElevenLabsClient.keyterms(from: ["un deux trois quatre cinq six"]).isEmpty)
        #expect(ElevenLabsClient.keyterms(from: [String(repeating: "a", count: 49)]).count == 1)
        #expect(ElevenLabsClient.keyterms(from: [String(repeating: "a", count: 50)]).isEmpty)
    }

    @Test("Scribe keyterms are deduplicated and capped")
    func keytermsCapped() {
        #expect(ElevenLabsClient.keyterms(from: ["Mistral", "mistral"]) == ["Mistral"])
        #expect(ElevenLabsClient.keyterms(from: (0..<150).map { "terme\($0)" }).count == 100)
    }


}

/// The journal's counters are what make a day of dictation readable at a glance, so they
/// have to count edits and not merely differences: a single inserted word must not read as
/// a rewrite of the whole sentence that follows it.
@Suite("DictationJournal")
struct DictationJournalTests {
    @Test("an identical text counts no change")
    func identical() {
        #expect(DictationJournal.changedWords(from: "bonjour tout le monde", to: "bonjour tout le monde") == 0)
    }

    @Test("one substitution counts one word")
    func substitution() {
        #expect(DictationJournal.changedWords(from: "bonjour tout le monde", to: "bonjour tout le peuple") == 1)
    }

    @Test("an inserted word does not shift everything after it")
    func insertion() {
        #expect(DictationJournal.changedWords(from: "je vais le faire", to: "je vais bien le faire") == 1)
    }

    @Test("an emptied text counts every word it had")
    func emptied() {
        #expect(DictationJournal.changedWords(from: "bonjour tout le monde", to: "") == 4)
    }
}
