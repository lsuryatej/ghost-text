import Foundation

/// Finishes the word you are part-way through, with no model involved.
///
/// Two problems it solves. The model is silent about a quarter of the time - it
/// answers with a bare newline or full stop when it thinks the sentence is done -
/// and showing nothing that often reads as broken. And even when it does answer,
/// there is a round trip first. This costs nothing and is available immediately,
/// so there is something on screen while the model thinks.
///
/// Candidates come from the document you are already writing in before any
/// dictionary, because a word you have used on this page is far likelier than a
/// word that merely exists. That also means the good suggestions are yours:
/// names, jargon and product names a general dictionary has never heard of.
public struct InstantCompleter: Sendable {
    /// Below this a fragment matches far too much to guess usefully.
    public static let minimumFragment = 3

    /// Sorted lowercase, so a prefix lookup is a binary search rather than a
    /// scan. The system word list is 236k entries and this runs on every
    /// keystroke, so a linear scan would cost more than the model does.
    private let dictionary: [String]

    public init(dictionary: [String] = []) {
        self.dictionary = dictionary.map { $0.lowercased() }.sorted()
    }

    /// Whether `word` is itself a complete dictionary entry, not merely a
    /// prefix of one. Used to tell "the user finished this word" from "the
    /// user is still typing it" when a fragment could be read either way.
    public func isCompleteWord(_ word: String) -> Bool {
        let lowered = word.lowercased()
        var low = 0
        var high = dictionary.count
        while low < high {
            let mid = (low + high) / 2
            if dictionary[mid] < lowered { low = mid + 1 } else { high = mid }
        }
        return low < dictionary.count && dictionary[low] == lowered
    }

    /// Shortest dictionary word extending `prefix`, or nil.
    func dictionaryMatch(prefix: String) -> String? {
        var low = 0
        var high = dictionary.count
        while low < high {
            let mid = (low + high) / 2
            if dictionary[mid] < prefix { low = mid + 1 } else { high = mid }
        }
        var best: String?
        var index = low
        // Common prefixes can match thousands of words; the best candidate is
        // near the front of the run, so cap the scan.
        while index < dictionary.count, index < low + 512, dictionary[index].hasPrefix(prefix) {
            let candidate = dictionary[index]
            if candidate.count > prefix.count, best == nil || candidate.count < best!.count {
                best = candidate
            }
            index += 1
        }
        return best
    }

    /// The trailing partial word, or nil if the buffer does not end mid-word.
    public static func fragment(in buffer: String) -> String? {
        guard let last = buffer.last, last.isLetter else { return nil }
        let fragment = String(buffer.reversed().prefix(while: { $0.isLetter }).reversed())
        return fragment.count >= minimumFragment ? fragment : nil
    }

    /// Returns the *remainder* of the word, ready to append, or nil.
    public func complete(buffer: String, context: String) -> String? {
        guard let fragment = Self.fragment(in: buffer) else { return nil }
        let lowered = fragment.lowercased()

        var counts: [String: Int] = [:]
        for word in Self.words(in: context) {
            let candidate = word.lowercased()
            guard candidate.count > fragment.count, candidate.hasPrefix(lowered) else { continue }
            counts[candidate, default: 0] += 1
        }

        // Most used on this page wins; ties go to the shorter word, which is the
        // safer guess when there is nothing else to separate them.
        let best = counts.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key.count > rhs.key.count
        }?.key

        let chosen = best ?? dictionaryMatch(prefix: lowered)

        guard let chosen else { return nil }
        return String(chosen.dropFirst(fragment.count))
    }

    static func words(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && $0 != "'" })
            .map(String.init)
            .filter { $0.count > minimumFragment }
    }
}
