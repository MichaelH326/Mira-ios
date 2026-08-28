import Foundation
import AVFoundation
import SherpaOnnxC

/// The on-device voice: a Piper VITS model through sherpa-onnx.
///
/// This replaced Kokoro-82M, which sounded a little better and cost far too
/// much for it. Kokoro's int8 weights are 110MB against 60MB here, its voice
/// bank another 52MB, and — the part that mattered more — it is 82M
/// parameters of transformer to run before the first sample comes out, so
/// there was an audible beat between Mira finishing thinking and starting to
/// talk. Piper's medium models are a fraction of that to run, which turns
/// that beat into nothing.
///
/// The model lives in the app bundle under `voice/`; when it isn't there —
/// a build made without it — `CallViewModel` falls back to `Speaker`.
@MainActor
final class LocalVoice: VoiceOutput {

    private let synthesizer: LocalSynthesizer
    private let queue = SpeechQueueState()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat

    /// Sentences are synthesized in the order they were queued by chaining
    /// each onto the previous one — actors don't promise FIFO on their own,
    /// and a reply whose sentences play out of order is worse than a slow one.
    private var tail: Task<Void, Never>?

    /// Bumped by `stop()`. Work queued before the bump is discarded rather
    /// than played: cancelling the tail doesn't cancel a sentence already
    /// mid-synthesis, and that one would otherwise restart the audio engine
    /// and talk over the user after an interruption.
    private var generation = 0

    var onFinishedSpeaking: (() -> Void)? {
        get { queue.onDrained }
        set { queue.onDrained = newValue }
    }

    /// VITS reports no word boundaries, so the caption's timings are
    /// estimated from each sentence's own duration.
    var onCaption: ((Caption?) -> Void)?

    /// Captions are chained the same way synthesis is, so each sentence's
    /// caption begins as the one before it stops — which is when its audio
    /// starts playing.
    private var captionTail: Task<Void, Never>?

    var describedVoice: String { "On device · voice \(LocalVoice.chosenSpeaker + 1)" }

    /// Read at synthesis time rather than held, so a change in Settings
    /// applies to the very next sentence.
    static var chosenSpeaker: Int32 {
        Int32(max(0, UserDefaults.standard.integer(forKey: Prefs.voiceKey)))
    }

    /// Clamped to what this model actually has, so a preference carried over
    /// from a build with more voices can't ask for a speaker that isn't there.
    private var speakerID: Int32 {
        min(LocalVoice.chosenSpeaker, max(0, synthesizer.speakerCount - 1))
    }

    static var chosenSpeed: Float {
        let stored = UserDefaults.standard.double(forKey: Prefs.speedKey)
        return stored > 0 ? Float(min(max(stored, 0.5), 2.0)) : 1.0
    }

    /// Returns nil when the model isn't bundled, so the caller can fall back.
    static func makeIfAvailable() -> LocalVoice? {
        guard let directory = ModelLocator.bundledVoiceDirectory() else { return nil }
        return try? LocalVoice(directory: directory)
    }

    init(directory: URL) throws {
        synthesizer = try LocalSynthesizer(directory: directory)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: synthesizer.sampleRate,
                                         channels: 1) else {
            throw LocalSynthesizer.EngineError.audioFormatUnavailable
        }
        self.format = format

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.volume = 1
        engine.mainMixerNode.outputVolume = 1
    }

    func setExpectingMore(_ expecting: Bool) {
        queue.setExpectingMore(expecting)
    }

    func enqueue(_ sentence: String) {
        let spoken = SpeechText.forSpeaking(sentence)
        guard !spoken.isEmpty else { return }
        queue.added()

        let previous = tail
        let token = generation
        tail = Task { [weak self] in
            // Wait for the sentence before this one to be handed to the player,
            // so playback order matches the order Mira generated them.
            _ = await previous?.value
            guard let self, !Task.isCancelled, self.generation == token else { return }
            let speaker = self.speakerID
            let samples = await self.synthesizer.synthesize(
                spoken, speaker: speaker, speed: LocalVoice.chosenSpeed)
            guard !Task.isCancelled, self.generation == token else { return }
            self.play(samples, saying: spoken)
        }
    }

    func stop() {
        generation &+= 1
        tail?.cancel()
        tail = nil
        player.stop()
        if engine.isRunning { engine.stop() }
        captionTail?.cancel()
        captionTail = nil
        onCaption?(nil)
        queue.reset()
    }

    private func play(_ samples: [Float], saying text: String) {
        guard !samples.isEmpty else {
            // Synthesis failed or produced nothing — don't strand the count.
            queue.finishedOne()
            return
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            queue.finishedOne()
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let gain = Self.gain(for: samples)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        if gain != 1 {
            for index in 0..<samples.count { channel[index] *= gain }
        }

        do {
            try startEngineIfNeeded()
        } catch {
            queue.finishedOne()
            return
        }

        startCaption(for: text,
                     duration: Double(samples.count) / synthesizer.sampleRate)

        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.queue.finishedOne() }
        }
        if !player.isPlaying { player.play() }
    }

    /// Normalises a sentence so it plays at a consistent, full level.
    ///
    /// The model's output peaks well below full scale and varies sentence to
    /// sentence, which is the other half of why Mira was quiet. The gain is
    /// capped so a near-silent buffer is not amplified into its own noise
    /// floor, and the target leaves headroom so nothing clips.
    private static func gain(for samples: [Float]) -> Float {
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > 0.01 else { return 1 }
        return min(0.95 / peak, 6)
    }

    /// Runs this sentence's caption after the previous sentence's, which is
    /// when its audio starts.
    private func startCaption(for text: String, duration: TimeInterval) {
        let words = Caption.words(in: text)
        guard !words.isEmpty, duration > 0 else { return }
        let starts = CaptionClock.estimatedStarts(for: words, duration: duration)

        let previous = captionTail
        let token = generation
        captionTail = Task { [weak self] in
            _ = await previous?.value
            guard let self, !Task.isCancelled, self.generation == token else { return }
            self.onCaption?(Caption(words: words, index: 0, isMira: true))
            await CaptionClock.walk(starts: starts, endsAt: duration) { index in
                guard self.generation == token else { return }
                self.onCaption?(Caption(words: words, index: index, isMira: true))
            }
        }
    }

    private func startEngineIfNeeded() throws {
        guard !engine.isRunning else { return }
        // The session is normally already configured by SpeechListener, but
        // Mira can speak before anyone has spoken to her — and it has to be
        // the playback configuration either way, not the recording one.
        AudioSession.beginPlayback()
        engine.prepare()
        try engine.start()
    }
}

/// Serializes access to the sherpa-onnx TTS handle, which is not thread-safe,
/// and keeps synthesis off the main thread.
actor LocalSynthesizer {

    enum EngineError: LocalizedError {
        case filesMissing(String)
        case initializationFailed
        case audioFormatUnavailable

        var errorDescription: String? {
            switch self {
            case .filesMissing(let what):  return "The on-device voice is missing \(what)."
            case .initializationFailed:    return "The on-device voice couldn't be loaded."
            case .audioFormatUnavailable:  return "Couldn't open an audio output for the on-device voice."
            }
        }
    }

    private let tts: OpaquePointer
    nonisolated let sampleRate: Double
    /// How many voices this model has. The picker offers six; the model has
    /// many more, and a build with fewer must not be asked for one it lacks.
    nonisolated let speakerCount: Int32

    init(directory: URL) throws {
        let model = directory.appendingPathComponent("model.onnx")
        let tokens = directory.appendingPathComponent("tokens.txt")
        let espeak = directory.appendingPathComponent("espeak-ng-data")

        for (url, label) in [(model, "model.onnx"), (tokens, "tokens.txt"),
                             (espeak, "espeak-ng-data")] {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw EngineError.filesMissing(label)
            }
        }

        // The config holds borrowed C strings; they must outlive the create
        // call, so they're owned here and released once it returns.
        var owned: [UnsafeMutablePointer<CChar>] = []
        defer { owned.forEach { free($0) } }
        func cString(_ value: String) -> UnsafePointer<CChar>? {
            guard let copy = strdup(value) else { return nil }
            owned.append(copy)
            return UnsafePointer(copy)
        }

        var vits = SherpaOnnxOfflineTtsVitsModelConfig()
        vits.model = cString(model.path)
        vits.tokens = cString(tokens.path)
        // With espeak-ng data present the lexicon is ignored, and Piper models
        // ship no lexicon: espeak does the phonemising.
        vits.data_dir = cString(espeak.path)
        vits.lexicon = cString("")
        // The three scales the model card asks for. A zeroed struct would
        // leave all of them at 0, which does not fail — it just synthesises
        // flat, rushed speech, so they have to be set explicitly.
        vits.noise_scale = 0.333
        vits.noise_scale_w = 0.333
        vits.length_scale = 1.0

        var modelConfig = SherpaOnnxOfflineTtsModelConfig()
        modelConfig.vits = vits
        modelConfig.provider = cString("cpu")
        modelConfig.debug = 0
        // Leaves cores for the LLM, which is generating the next sentence.
        modelConfig.num_threads = Int32(max(1, min(2, ProcessInfo.processInfo.activeProcessorCount - 2)))

        var config = SherpaOnnxOfflineTtsConfig()
        config.model = modelConfig
        config.max_num_sentences = 1
        config.silence_scale = 0.2

        guard let handle = withUnsafePointer(to: &config, { SherpaOnnxCreateOfflineTts($0) }) else {
            throw EngineError.initializationFailed
        }
        tts = handle

        let rate = SherpaOnnxOfflineTtsSampleRate(handle)
        sampleRate = rate > 0 ? Double(rate) : 22050
        speakerCount = max(1, SherpaOnnxOfflineTtsNumSpeakers(handle))
    }

    deinit {
        SherpaOnnxDestroyOfflineTts(tts)
    }

    /// Returns mono float samples at `sampleRate`, or an empty array on failure.
    func synthesize(_ text: String, speaker: Int32 = 0, speed: Float = 1.0) -> [Float] {
        guard let generated = text.withCString({
            SherpaOnnxOfflineTtsGenerate(tts, $0, speaker, speed)
        }) else { return [] }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(generated) }

        let count = Int(generated.pointee.n)
        guard count > 0, let samples = generated.pointee.samples else { return [] }
        return [Float](UnsafeBufferPointer(start: samples, count: count))
    }
}
