import Foundation

/// One line of caption: what is being said, and which word is being said now.
///
/// This is what the main screen shows instead of a scrolling transcript —
/// closed captions for the conversation. The full transcript is still there,
/// one tap away in the header and in Previous Sessions.
struct Caption: Equatable {
    var words: [String]
    /// Index of the word being spoken. Words before it have been said;
    /// words after it have not. `-1` before the first word starts.
    var index: Int
    /// Mira speaking, as opposed to a live transcription of you.
    var isMira: Bool

    var isEmpty: Bool { words.isEmpty }

    static func words(in sentence: String) -> [String] {
        sentence.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// A caption for text with no timing behind it — your own speech as it is
    /// transcribed, where every word shown has already been said.
    static func said(_ text: String, isMira: Bool) -> Caption {
        let words = Caption.words(in: text)
        return Caption(words: words, index: words.count - 1, isMira: isMira)
    }
}

/// Walks a caption through its words in time with the audio.
///
/// Both voices end up here, but they get their timings very differently:
/// Edge reports real word boundaries from the service, and Kokoro has none,
/// so its are estimated from the sentence's own duration. Either way what
/// arrives is a start time per word, and this walks them.
///
/// A plain async function rather than an object, so each sentence's caption
/// can be chained onto the previous one exactly the way its audio is. That
/// chaining is what keeps the caption on the right sentence: a caption runs
/// for its sentence's duration, so the next one begins as the next sentence
/// starts playing, with no separate bookkeeping of where the playhead is.
enum CaptionClock {

    /// Splits `duration` across `words` in proportion to their length.
    ///
    /// An estimate, not a measurement: without word boundaries from the
    /// engine there is nothing better to go on. Longer words do take longer
    /// to say, so weighting by character count tracks real speech closely
    /// enough over one sentence that the highlight lands on the right word.
    static func estimatedStarts(for words: [String], duration: TimeInterval) -> [TimeInterval] {
        guard !words.isEmpty, duration > 0 else { return [] }
        // The constant is the gap between words, which does not scale with
        // their length; without it short words race ahead of the audio.
        let weights = words.map { Double($0.count) + 2.0 }
        let total = weights.reduce(0, +)
        guard total > 0 else { return [] }

        var starts: [TimeInterval] = []
        starts.reserveCapacity(words.count)
        var elapsed: Double = 0
        for weight in weights {
            starts.append(duration * elapsed / total)
            elapsed += weight
        }
        return starts
    }

    /// Reports each word index as its start time is reached, then returns
    /// once `endsAt` has passed — so the caller's chain advances in step with
    /// the audio rather than a sentence ahead of it.
    @MainActor
    static func walk(starts: [TimeInterval], endsAt: TimeInterval,
                     onWord: (Int) -> Void) async {
        // Deadlines are all measured from one start, so a late wake-up does
        // not push every following word further behind the audio.
        let began = Date()
        for (index, start) in starts.enumerated() {
            await wait(until: start, from: began)
            guard !Task.isCancelled else { return }
            onWord(index)
        }
        await wait(until: endsAt, from: began)
    }

    private static func wait(until offset: TimeInterval, from start: Date) async {
        let due = offset - Date().timeIntervalSince(start)
        guard due > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(due * 1_000_000_000))
    }
}
