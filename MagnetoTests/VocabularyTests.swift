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

    @Test("Voxtral takes single words, so multi-word terms are split")
    func contextBiasSplits() {
        #expect(VoxtralClient.contextBias(from: ["Claude Haiku"]) == ["Claude", "Haiku"])
        #expect(VoxtralClient.contextBias(from: ["ElevenLabs Scribe v2"]) == ["ElevenLabs", "Scribe", "v2"])
        #expect(VoxtralClient.contextBias(from: ["dv1,"]) == ["dv1"])
    }

    @Test("Voxtral context_bias is deduplicated and capped")
    func contextBiasCapped() {
        #expect(VoxtralClient.contextBias(from: ["Mistral", "mistral"]) == ["Mistral"])
        #expect(VoxtralClient.contextBias(from: (0..<150).map { "terme\($0)" }).count == 100)
    }
}
