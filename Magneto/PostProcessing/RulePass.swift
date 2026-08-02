import Foundation

enum RulePass {
    private static let nnbsp = "\u{202F}"
    private static let apostrophe = "\u{2019}"

    static func clean(_ raw: String, customWords: [String], frenchTypography: Bool) -> String {
        let normalized = raw
            .replacingOccurrences(of: "\u{2026}", with: "...")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return normalized }

        let (masked, protectedTokens) = mask(normalized)
        var text = normalizeQuotes(masked)

        text = replace(text, #"(?<=[,.;:?!])\s*\.{3,}"#, "")
        text = replace(text, #"\s*\.{3,}\s*(?=[,.;:?!])"#, "")
        text = replace(text, #"\s*\.{3,}\s*$"#, ".")
        text = resolveEllipses(text, customWords: customWords)
        text = replace(text, #"\s*\.{3,}\s*"#, " ")

        text = replace(text, #"^[\s,]+"#, "")
        text = replace(text, #"[ \t]{2,}"#, " ")
        text = replace(text, #"\s+([,\.?!;:])"#, "$1")
        text = replace(text, #",\s*,"#, ",")
        text = replace(text, #",\s*\."#, ".")
        text = replace(text, #"(?<![0-9])([,;:?!])(?=[\p{L}])"#, "$1 ")
        text = capitalizeAfterSentenceEnd(text)

        if frenchTypography {
            text = replace(text, #"(?<=[\p{L}\p{N}])([?!;])"#, "\(nnbsp)$1")
            text = replace(text, #"(?<=[\p{L}])(:)"#, "\(nnbsp)$1")
        }

        text = restore(text, protectedTokens)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = text.first, first.isLowercase {
            text = first.uppercased() + text.dropFirst()
        }
        return text
    }

    /// French guillemets and curly quotes are rewritten as the straight quote the
    /// keyboard produces, and the thin spaces they carry are dropped.
    static func normalizeQuotes(_ text: String) -> String {
        var result = replace(text, "[\u{00AB}\u{201C}\u{201F}][ \u{202F}\u{00A0}]*", "\"")
        result = replace(result, "[ \u{202F}\u{00A0}]*[\u{00BB}\u{201D}]", "\"")
        return result
    }

    /// Words that can open a new clause. When a pause is followed by one of them, the
    /// pause was a real sentence break and deserves a comma.
    private static let sentenceStarters: Set<String> = [
        "alors", "donc", "et", "mais", "ou", "puis", "ensuite", "enfin", "bref", "voilà",
        "après", "avant", "pendant", "parce", "car", "comme", "quand", "lorsque", "si",
        "je", "j'ai", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles",
        "ce", "cet", "cette", "ces", "c'est", "ça", "cela", "celui", "celle",
        "que", "qui", "quoi", "dont", "là", "ici", "oui", "non", "peut-être",
        "vraiment", "juste", "aussi", "même", "encore", "déjà", "toujours", "jamais",
        "finalement", "globalement", "typiquement", "du", "le", "la", "les", "un", "une",
    ]

    /// Words that cannot end a clause: a pause right after one of them was a hesitation
    /// inside a phrase, so the fragments are simply rejoined with a space.
    private static let danglingWords: Set<String> = [
        "à", "au", "aux", "de", "du", "des", "le", "la", "les", "un", "une", "d'un", "d'une",
        "et", "ou", "mais", "donc", "car", "que", "qui", "dont", "où", "quand", "si", "comme",
        "pour", "dans", "sur", "sous", "avec", "sans", "par", "vers", "chez", "entre", "en",
        "mon", "ma", "mes", "son", "sa", "ses", "notre", "nos", "votre", "vos", "leur", "leurs",
        "ce", "cet", "cette", "ces", "je", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles",
        "faut", "va", "vais", "vas", "peux", "peut", "doit", "dois", "veux", "veut",
        "est", "sont", "suis", "es", "a", "ai", "as", "ont", "avons", "avez", "était", "sera",
        "plus", "moins", "très", "bien", "tout", "tous", "toute", "toutes", "aussi", "vraiment",
    ]

    /// A pause rendered as "..." mid-sentence: rejoin the two fragments with a comma
    /// only when a new clause really starts, otherwise with a plain space. Custom
    /// vocabulary keeps its canonical casing; unknown capitalized words are left alone
    /// since they are most likely proper nouns.
    private static func resolveEllipses(_ text: String, customWords: [String]) -> String {
        let wordClass = "[\\p{L}\\p{N}'\(apostrophe)-]"
        guard let regex = try? NSRegularExpression(
            pattern: "(\(wordClass)*)\\s*\\.{3,}\\s*(\(wordClass)*)"
        ) else {
            return text
        }
        let canonical = Dictionary(
            customWords.map { (normalizedKey($0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let mutable = NSMutableString(string: text)
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: mutable.length))
        for match in matches.reversed() {
            let before = mutable.substring(with: match.range(at: 1))
            var after = mutable.substring(with: match.range(at: 2))
            let afterKey = normalizedKey(after)
            let opensClause = sentenceStarters.contains(afterKey)

            if let known = canonical[afterKey] {
                after = known
            } else if opensClause, let first = after.first, first.isUppercase {
                after = first.lowercased() + after.dropFirst()
            }

            let separator: String
            if before.isEmpty || after.isEmpty {
                separator = ""
            } else if opensClause, !danglingWords.contains(normalizedKey(before)) {
                separator = ", "
            } else {
                separator = " "
            }
            mutable.replaceCharacters(in: match.range, with: before + separator + after)
        }
        return mutable as String
    }

    private static func capitalizeAfterSentenceEnd(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?<=[.!?])(\s+)(\p{Ll})"#) else {
            return text
        }
        let mutable = NSMutableString(string: text)
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: mutable.length))
        for match in matches.reversed() {
            let spacing = mutable.substring(with: match.range(at: 1))
            let letter = mutable.substring(with: match.range(at: 2)).uppercased()
            mutable.replaceCharacters(in: match.range, with: spacing + letter)
        }
        return mutable as String
    }

    private static func normalizedKey(_ word: String) -> String {
        word.replacingOccurrences(of: apostrophe, with: "'").lowercased()
    }

    private static let protectedPattern =
        #"(?:[a-zA-Z][a-zA-Z0-9+.-]*://\S*[\w/]|www\.[\w.-]+[\w/]|[\w.+-]+@[\w-]+\.[\w.-]*\w)"#

    /// URLs and e-mail addresses are pulled out before the punctuation and typography
    /// rules run, otherwise "https://leetchi.com/pot?id=42" comes back mangled.
    private static func mask(_ text: String) -> (String, [String]) {
        guard let regex = try? NSRegularExpression(pattern: protectedPattern) else {
            return (text, [])
        }
        let mutable = NSMutableString(string: text)
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: mutable.length))
        guard !matches.isEmpty else { return (text, []) }
        var tokens = [String](repeating: "", count: matches.count)
        for (index, match) in matches.enumerated().reversed() {
            tokens[index] = mutable.substring(with: match.range)
            mutable.replaceCharacters(in: match.range, with: "\u{FFFC}\(index)\u{FFFC}")
        }
        return (mutable as String, tokens)
    }

    private static func restore(_ text: String, _ tokens: [String]) -> String {
        var result = text
        for (index, token) in tokens.enumerated() {
            result = result.replacingOccurrences(of: "\u{FFFC}\(index)\u{FFFC}", with: token)
        }
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
