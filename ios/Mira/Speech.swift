import Foundation
import AVFoundation
import Speech

/// On-device speech-to-text. Reports partial results so the UI can show what
/// it's hearing, and detects when the speaker has stopped to end the turn.
@MainActor
final class SpeechListener: NSObject, ObservableObject {

    @Published private(set) var partialText: String = ""
    @Published private(set) var isListening = false
    @Published private(set) var audioLevel: Float = 0

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var onTurn: ((TurnOutcome) -> Void)?
    private var usingOnDevice = false

    /// Dropped after on-device recognition fails once: some devices report
    /// support without actually having the offline asset installed, and the
    /// request then fails the moment it starts.
    private var allowOnDevice = true

    /// How a turn ended. Silence is normal and says nothing to the user;
    /// a failure needs to be visible, or the button just blinks off with no
    /// explanation.
    enum TurnOutcome {
        case heard(String)
        case silence
        case failed(String)
    }

    enum ListenError: LocalizedError {
        case recognizerUnavailable

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                return "Speech recognition isn't available right now. Check Settings ▸ General ▸ Keyboard ▸ Enable Dictation."
            }
        }
    }

    /// How long a pause ends the user's turn.
    var endOfTurnSilence: TimeInterval = 1.1

    /// How long to wait for a first word before giving the turn back. Without
    /// this the turn only ever ended on a recognition result, so tapping to
    /// talk and staying quiet left the app listening forever.
    var openingSilence: TimeInterval = 6

    static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    /// Starts a turn. `onTurn` is called exactly once when the turn ends, so
    /// the caller always gets its state machine back.
    func start(onTurn: @escaping (TurnOutcome) -> Void) throws {
        guard !isListening else { return }
        guard let recognizer, recognizer.isAvailable else {
            throw ListenError.recognizerUnavailable
        }
        self.onTurn = onTurn
        partialText = ""

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat,
                                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keep audio on the device; also works with no network.
        request.requiresOnDeviceRecognition = allowOnDevice && recognizer.supportsOnDeviceRecognition
        usingOnDevice = request.requiresOnDeviceRecognition
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            self?.updateLevel(from: buffer)
        }

        engine.prepare()
        try engine.start()
        isListening = true
        restartSilenceTimer(after: openingSilence)

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    let heard = result.bestTranscription.formattedString
                    self.partialText = heard
                    // Recognition delivers early results that are still empty.
                    // Switching to the short end-of-turn window on one of those
                    // ends the turn about a second after the tap, before the
                    // user has said anything — keep the opening window until
                    // there is actually something to end.
                    let started = !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    self.restartSilenceTimer(after: started ? self.endOfTurnSilence
                                                            : self.openingSilence)
                }
                if let error {
                    self.finishTurn(error: error)
                } else if result?.isFinal ?? false {
                    self.finishTurn()
                }
            }
        }
    }

    /// Stops listening and reports how the turn ended.
    func finishTurn(error: Error? = nil) {
        guard isListening else { return }
        let text = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        let deliver = onTurn
        let wasOnDevice = usingOnDevice
        stop()

        if !text.isEmpty {
            deliver?(.heard(text))
            return
        }
        guard let error, !Self.isSilence(error) else {
            deliver?(.silence)
            return
        }
        if wasOnDevice && allowOnDevice {
            // Reported as supported, then failed with nothing transcribed —
            // the offline asset almost certainly isn't installed. Use the
            // network recognizer for the rest of the session.
            allowOnDevice = false
            deliver?(.failed("On-device speech recognition wouldn't start. Switching to network recognition — tap to talk again."))
            return
        }
        deliver?(.failed(error.localizedDescription))
    }

    /// Errors that mean "nothing was said" or "we cancelled it ourselves",
    /// as opposed to a recognizer that failed to run.
    private static func isSilence(_ error: Error) -> Bool {
        let error = error as NSError
        guard error.domain == "kAFAssistantErrorDomain" else { return false }
        return [216, 301, 1110].contains(error.code)
    }

    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        onTurn = nil
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
        audioLevel = 0
    }

    private func restartSilenceTimer(after interval: TimeInterval) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finishTurn() }
        }
    }

    private nonisolated func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        var sum: Float = 0
        for index in 0..<frames { sum += channel[index] * channel[index] }
        let rms = (sum / Float(frames)).squareRoot()
        let level = min(1, max(0, (20 * log10(max(rms, 1e-7)) + 50) / 50))
        Task { @MainActor [weak self] in self?.audioLevel = level }
    }
}

/// Apple's built-in synthesizer. The fallback voice: always available, and
/// noticeably better if the user has downloaded a Premium voice under
/// Settings ▸ Accessibility ▸ Spoken Content ▸ Voices.
@MainActor
final class Speaker: NSObject, VoiceOutput, AVSpeechSynthesizerDelegate {

    private let synthesizer = AVSpeechSynthesizer()
    private let queue = SpeechQueueState()

    var onFinishedSpeaking: (() -> Void)? {
        get { queue.onDrained }
        set { queue.onDrained = newValue }
    }

    var describedVoice: String {
        Self.preferredVoice().map { "Apple · \($0.name)" } ?? "Apple"
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func setExpectingMore(_ expecting: Bool) {
        queue.setExpectingMore(expecting)
    }

    func enqueue(_ sentence: String) {
        let spoken = SpeechText.forSpeaking(sentence)
        guard !spoken.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = Self.preferredVoice()
        utterance.rate = 0.52          // just above default; conversational
        utterance.pitchMultiplier = 1.05
        utterance.postUtteranceDelay = 0.05
        queue.added()
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        queue.reset()
    }

    private static func preferredVoice() -> AVSpeechSynthesisVoice? {
        // Prefer the higher-quality voices when the user has downloaded them.
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        if let premium = voices.first(where: { $0.quality == .premium }) { return premium }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) { return enhanced }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.queue.finishedOne() }
    }

    // Cancelled utterances never report `didFinish`; without this the
    // outstanding count would never return to zero after an interruption.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.queue.finishedOne() }
    }
}

/// Text preparation shared by the UI and the speech synthesizer.
enum SpeechText {

    /// Groups streamed chunks into complete sentences — the unit we speak.
    /// Returns finished sentences and whatever remains buffered.
    static func sentences(from buffer: String) -> (complete: [String], remainder: String) {
        var complete: [String] = []
        var remainder = buffer

        while let range = remainder.range(of: #"[.!?…]+["')\]]?\s"#, options: .regularExpression) {
            let sentence = String(remainder[..<range.upperBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { complete.append(sentence) }
            remainder = String(remainder[range.upperBound...])
        }
        return (complete, remainder)
    }

    /// Mirrors `clean_for_speech` + `numbers_to_speech` in `voice/run_mira.py`:
    /// strip anything a TTS engine would stumble over, and say numbers as words.
    static func forSpeaking(_ text: String) -> String {
        var output = text
        output = output.replacingOccurrences(of: #"[*_`>|~\[\]{}#^\\]"#,
                                             with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: #"https?://\S+"#,
                                             with: "", options: .regularExpression)
        output = output.unicodeScalars.filter { scalar in
            !(0x1F000...0x1FAFF).contains(scalar.value) && !(0x2600...0x27BF).contains(scalar.value)
        }.reduce(into: "") { $0.unicodeScalars.append($1) }
        output = NumberSpeech.spellOut(in: output)
        return output.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Says digits the way a person would — the Swift counterpart of
/// `numbers_to_speech` in `voice/run_mira.py`.
enum NumberSpeech {

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en-US")
        return formatter
    }()

    private static func words(_ value: Int) -> String {
        formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func spellOut(in text: String) -> String {
        var output = text

        // 15-20 -> 15 to 20
        output = output.replacingOccurrences(of: #"(\d)\s*-\s*(\d)"#, with: "$1 to $2",
                                             options: .regularExpression)
        output = replace(in: output, pattern: #"\$\s*([\d,]+)(?:\.(\d{2}))?"#) { groups in
            let whole = groups[0].replacingOccurrences(of: ",", with: "")
            guard let amount = Int(whole) else { return nil }
            var spoken = words(amount) + (amount == 1 ? " dollar" : " dollars")
            if groups.count > 1, let cents = Int(groups[1]), cents > 0 {
                spoken += " and " + words(cents) + " cents"
            }
            return spoken
        }
        output = replace(in: output, pattern: #"([\d,]+(?:\.\d+)?)\s*%"#) { groups in
            let value = groups[0].replacingOccurrences(of: ",", with: "")
            guard let number = Double(value) else { return nil }
            let spoken = number == number.rounded()
                ? words(Int(number))
                : (formatter.string(from: NSNumber(value: number)) ?? value)
            return spoken + " percent"
        }
        output = replace(in: output, pattern: #"(?<![A-Za-z\d])[\d,]+(?:\.\d+)?(?![A-Za-z\d])"#) { groups in
            let raw = groups[0]
            if raw.contains(".") {
                let parts = raw.split(separator: ".")
                guard let whole = Int(parts[0].replacingOccurrences(of: ",", with: "")) else { return nil }
                let decimals = parts.count > 1 ? parts[1].compactMap { $0.wholeNumberValue }
                    .map { words($0) }.joined(separator: " ") : ""
                return words(whole) + (decimals.isEmpty ? "" : " point " + decimals)
            }
            guard let value = Int(raw.replacingOccurrences(of: ",", with: "")) else { return nil }
            // Year-like numbers read as years: 1995 -> nineteen ninety-five
            if raw.count == 4, (1100...2099).contains(value), value % 1000 != 0 {
                let high = value / 100, low = value % 100
                if low == 0 { return words(high) + " hundred" }
                return words(high) + " " + (low < 10 ? "oh " + words(low) : words(low))
            }
            return words(value)
        }
        return output
    }

    private static func replace(in text: String, pattern: String,
                                transform: ([String]) -> String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var output = text
        for match in matches.reversed() {
            var groups: [String] = []
            for index in 1..<match.numberOfRanges {
                if let range = Range(match.range(at: index), in: text) {
                    groups.append(String(text[range]))
                }
            }
            if groups.isEmpty, let range = Range(match.range, in: text) {
                groups.append(String(text[range]))
            }
            guard let replacement = transform(groups),
                  let range = Range(match.range, in: output) else { continue }
            output.replaceSubrange(range, with: replacement)
        }
        return output
    }
}
