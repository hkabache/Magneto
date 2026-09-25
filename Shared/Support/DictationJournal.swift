import Foundation

/// Keeps each dictation, its audio and its text before and after the rules, in files of
/// its own and never in the system journal: the Diagnostic button copies that journal into
/// a support message, and the README promises it carries no dictated text. These files
/// carry it in clear, along with the recording, which is why they only exist while the
/// setting is on.
///
/// It exists because guessing was expensive. It is what showed that the LLM pass changed
/// ten words in a day, that a rule was gluing punctuation to the word before it, and that
/// another was capitalising fragments Scribe had deliberately left lowercase. The audio
/// matters as much as the text: it is what lets the same seconds be replayed through
/// another engine and compared word for word, on this voice and in this room.
enum DictationJournal {
    static func record(audio: URL?, raw: String, ruled: String, engine: String) {
        guard let journal = journalURL() else { return }
        let now = Date()
        let words = ruled.split(whereSeparator: \.isWhitespace).count
        let recording = audio.flatMap { keep($0, at: now) }
        let block = """

        ## \(display.string(from: now)) · \(engine)\(recording.map { " · \($0)" } ?? "")

        règles \(changedWords(from: raw, to: ruled)) mots sur \(words)

        - brut   : \(raw)
        - règles : \(ruled)

        """
        append(block, to: journal)
    }

    /// The number of words one text had to gain or lose to become the other, counted from
    /// the longest common subsequence so that a single inserted word does not read as a
    /// rewrite of everything after it.
    static func changedWords(from before: String, to after: String) -> Int {
        let source = before.split(whereSeparator: \.isWhitespace).map(String.init)
        let target = after.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !source.isEmpty, !target.isEmpty else { return max(source.count, target.count) }
        var table = [[Int]](repeating: [Int](repeating: 0, count: target.count + 1), count: source.count + 1)
        for i in 1...source.count {
            for j in 1...target.count {
                table[i][j] = source[i - 1] == target[j - 1]
                    ? table[i - 1][j - 1] + 1
                    : max(table[i - 1][j], table[i][j - 1])
            }
        }
        return max(source.count, target.count) - table[source.count][target.count]
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let filename: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH-mm-ss"
        return formatter
    }()

    private static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// The recording is copied and not moved: the pipeline still owns it and deletes it
    /// when it is done, and a debug aid has no business changing what production does.
    private static func keep(_ audio: URL, at moment: Date) -> String? {
        guard let folder = directory() else { return nil }
        let relative = "audio-\(day.string(from: moment))/\(filename.string(from: moment)).wav"
        let destination = folder.appendingPathComponent(relative)
        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard (try? FileManager.default.copyItem(at: audio, to: destination)) != nil else { return nil }
        return relative
    }

    /// Application Support on the Mac, where the README sends people. Documents on the
    /// iPhone: it is the only folder the Files app shows, and a journal nobody can open
    /// measures nothing.
    private static func directory() -> URL? {
        #if os(iOS)
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        #else
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Magneto")
        #endif
    }

    /// One file per day: a comparison is made on a day's worth of dictation, and a single
    /// growing file would mix the day being judged with the ones before it.
    private static func journalURL() -> URL? {
        directory()?.appendingPathComponent("dictees-\(day.string(from: Date())).md")
    }

    private static func append(_ block: String, to url: URL) {
        guard let data = block.data(using: .utf8) else { return }
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else {
            try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let header = """
            # Journal des dictées

            Ce fichier contient le texte dicté en clair, contrairement au journal système,
            et le dossier audio du jour contient les enregistrements eux-mêmes.
            Rien n'est écrit quand le réglage « Journal des dictées » est décoché.

            """
            guard let start = header.data(using: .utf8) else { return }
            try? (start + data).write(to: url)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
