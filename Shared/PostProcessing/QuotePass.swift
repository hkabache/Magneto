import Foundation

/// Straightens the quotation marks and apostrophes a transcription engine returns, and
/// nothing else.
///
/// There were eight other rules here: leading commas, doubled spaces, a space before a
/// comma, a doubled comma, a comma followed by a full stop, punctuation glued to the next
/// word, an ellipsis character turned into three dots, and casing forced at the start of a
/// sentence. Every one of them repaired the verbatim output of an engine that has since
/// left the chain. Counted on 1981 words from ElevenLabs and 1512 from Apple's local
/// model, they fired zero times, while two of them were actively damaging a correct text.
/// The count that mattered was this one: four guillemets in fifty dictations. The
/// apostrophes came with Voxtral, which writes the curly one in 4 dictations out of 83,
/// once mixed with straight ones in the same text, where Scribe and MAI never did in 925.
enum QuotePass {
    static func clean(_ raw: String) -> String {
        normalizeQuotes(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The narrow and non-breaking spaces French puts inside guillemets go with them:
    /// leaving them behind produced `" bonjour "`.
    static func normalizeQuotes(_ text: String) -> String {
        var result = replace(text, "[\u{00AB}\u{201C}\u{201F}][ \u{202F}\u{00A0}]*", "\"")
        result = replace(result, "[ \u{202F}\u{00A0}]*[\u{00BB}\u{201D}]", "\"")
        result = result.replacingOccurrences(of: "\u{2019}", with: "'")
        result = result.replacingOccurrences(of: "\u{2018}", with: "'")
        return result
    }

    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: template
        )
    }
}
