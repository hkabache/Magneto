import Foundation
import OSLog

/// The journal exists so a problem can be understood after the fact, on the Mac where
/// it happened and nowhere else. Two rules follow from that.
///
/// Level: anything worth reading later goes out at `.notice` or above, because `.info`
/// and `.debug` live in a memory buffer the system drops without warning, and a
/// journal that has already evaporated answers nothing.
///
/// Privacy: `Logger` masks dynamic strings as `<private>` unless they are marked
/// public, and only what someone may safely paste into a support message is marked so.
/// The dictated text and the API keys never reach the journal at all: the text lives in
/// `DictationJournal`, in files of its own, and only while that setting is on.
enum Log {
    /// Kept identical to the bundle identifier, which is what every `log show
    /// --predicate 'subsystem == "..."'` in the README filters on.
    static let subsystem = "com.hkabache.magneto"

    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    static let transcription = Logger(subsystem: subsystem, category: "transcription")
    static let paste = Logger(subsystem: subsystem, category: "paste")
    static let keychain = Logger(subsystem: subsystem, category: "keychain")
}

struct Stopwatch {
    private let start = ContinuousClock.now

    var milliseconds: Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds) * 1000
            + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}
