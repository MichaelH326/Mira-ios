import Foundation

/// A voice that speaks Mira's replies one sentence at a time.
///
/// Two implementations: `LocalVoice`, a neural model running through
/// sherpa-onnx, and `Speaker`, Apple's `AVSpeechSynthesizer`. The Apple one is
/// the fallback whenever the model isn't in the bundle, so a build without it
/// still talks.
@MainActor
protocol VoiceOutput: AnyObject {
    /// Called when a reply has finished being spoken — the queue has drained
    /// *and* generation has stopped feeding it.
    var onFinishedSpeaking: (() -> Void)? { get set }

    /// A short label for the engine in Settings.
    var describedVoice: String { get }

    /// Reports the sentence being spoken and how far through it the audio is,
    /// for the caption on the main screen. `nil` when nothing is being said.
    var onCaption: ((Caption?) -> Void)? { get set }

    /// `true` while a reply is still generating, so the gap between two
    /// sentences isn't mistaken for the end of Mira's turn.
    func setExpectingMore(_ expecting: Bool)

    /// Queues one sentence, spoken as soon as the ones before it finish.
    func enqueue(_ sentence: String)

    /// Drops everything queued and stops immediately.
    func stop()
}

/// Bookkeeping shared by both voices: a reply is over only once nothing is
/// outstanding *and* no more sentences are coming. Getting this wrong hands
/// the microphone back in the pause between two sentences.
@MainActor
final class SpeechQueueState {
    private var outstanding = 0
    private var expectingMore = false
    private(set) var isSpeaking = false

    /// Invoked once per reply, when the last sentence has finished.
    var onDrained: (() -> Void)?

    func setExpectingMore(_ expecting: Bool) {
        expectingMore = expecting
        if !expecting { notifyIfDrained() }
    }

    func added() {
        outstanding += 1
        isSpeaking = true
    }

    func finishedOne() {
        outstanding = max(0, outstanding - 1)
        notifyIfDrained()
    }

    /// Cancelled work never reports completion, so a stop resets the count
    /// outright rather than waiting for callbacks that won't arrive.
    func reset() {
        outstanding = 0
        expectingMore = false
        isSpeaking = false
    }

    private func notifyIfDrained() {
        guard outstanding == 0, !expectingMore, isSpeaking else { return }
        isSpeaking = false
        onDrained?()
    }
}
