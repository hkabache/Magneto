import Testing

/// The guard that decides whether the model's answer replaces the dictation. It is the
/// last thing standing between a paraphrase and the user's cursor.
@Suite("Garde-fou du nettoyage IA")
struct LLMPassTests {
    private let dictation = "bonjour tout le monde, comment allez-vous aujourd'hui"

    @Test("an answer that dropped too much text is refused")
    func lostText() {
        let input = String(repeating: "a", count: 100)
        let output = String(repeating: "a", count: 40)
        #expect(LLMPass.isSane(output, comparedTo: input, aggressiveFillers: false) == false)
        #expect(LLMPass.isSane(output, comparedTo: input, aggressiveFillers: true))
    }

    @Test("an answer that grew into a paraphrase is refused")
    func grewTooMuch() {
        let input = String(repeating: "a", count: 100)
        #expect(LLMPass.isSane(String(repeating: "a", count: 160), comparedTo: input, aggressiveFillers: false) == false)
        #expect(LLMPass.isSane(String(repeating: "a", count: 150), comparedTo: input, aggressiveFillers: false))
    }

    @Test("an empty answer is refused")
    func emptyAnswer() {
        #expect(LLMPass.isSane("   ", comparedTo: dictation, aggressiveFillers: false) == false)
    }

    @Test("a model that comments on the text instead of correcting it is refused")
    func metaAnswer() {
        #expect(LLMPass.isSane(
            "Voici le texte corrigé : bonjour tout le monde",
            comparedTo: dictation,
            aggressiveFillers: false
        ) == false)
        #expect(LLMPass.isSane(
            "```\nbonjour tout le monde\n```",
            comparedTo: "bonjour tout le monde",
            aggressiveFillers: false
        ) == false)
    }

    @Test("the same wording is kept when the speaker dictated it")
    func metaWordingDictated() {
        let spoken = "voici le texte que j'ai écrit hier soir pour la réunion"
        #expect(LLMPass.isSane(
            "Voici le texte que j'ai écrit hier soir pour la réunion.",
            comparedTo: spoken,
            aggressiveFillers: false
        ))
    }

    @Test("a plain correction goes through")
    func plainCorrection() {
        #expect(LLMPass.isSane(
            "Bonjour tout le monde, comment allez-vous aujourd'hui ?",
            comparedTo: dictation,
            aggressiveFillers: false
        ))
    }
}

/// A flat ceiling was cutting off exactly the dictations the pass has the most to correct:
/// five minutes of speech is around three thousand characters, and the model rewrites all
/// of them before answering.
@Suite("Budget du nettoyage IA")
struct LLMBudgetTests {
    @Test("une dictée de deux lignes n'attend pas dix secondes")
    func shortDictationWaitsLittle() {
        #expect(LLMPass.timeoutBudget(for: String(repeating: "a", count: 124)) < 2.5)
    }

    @Test("une dictée de cinq minutes a le temps d'être nettoyée")
    func longDictationGetsTime() {
        #expect(LLMPass.timeoutBudget(for: String(repeating: "a", count: 3_000)) > 8)
    }

    @Test("le budget reste borné, quelle que soit la longueur")
    func budgetStaysBounded() {
        #expect(LLMPass.timeoutBudget(for: String(repeating: "a", count: 200_000)) == 30)
    }
}
