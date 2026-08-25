import Foundation
import AVFoundation
import SherpaOnnxC

/// Kokoro-82M running on the phone through sherpa-onnx.
///
/// Markedly more natural than Apple's compact voices and still fully offline.
/// The model lives in the app bundle under `kokoro/`; when it isn't there —
/// a build made without it — `CallViewModel` falls back to `Speaker`.
@MainActor
final class KokoroVoice: VoiceOutput {

    private let synthesizer: KokoroSynthesizer
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

    var describedVoice: String { "Kokoro · voice \(KokoroVoice.chosenSpeaker + 1)" }

    /// Read at synthesis time rather than held, so a change in Settings
    /// applies to the very next sentence.
    static var chosenSpeaker: Int32 {
        Int32(max(0, UserDefaults.standard.integer(forKey: Prefs.voiceKey)))
    }

    static var chosenSpeed: Float {
        let stored = UserDefaults.standard.double(forKey: Prefs.speedKey)
        return stored > 0 ? Float(min(max(stored, 0.5), 2.0)) : 1.0
    }

    /// Returns nil when the model isn't bundled, so the caller can fall back.
    static func makeIfAvailable() -> KokoroVoice? {
        guard let directory = ModelLocator.bundledKokoroDirectory() else { return nil }
        return try? KokoroVoice(directory: directory)
    }

    init(directory: URL) throws {
        synthesizer = try KokoroSynthesizer(directory: directory)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: synthesizer.sampleRate,
                                         channels: 1) else {
            throw KokoroSynthesizer.EngineError.audioFormatUnavailable
        }
        self.format = format

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
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
            let samples = await self.synthesizer.synthesize(
                spoken, speaker: KokoroVoice.chosenSpeaker, speed: KokoroVoice.chosenSpeed)
            guard !Task.isCancelled, self.generation == token else { return }
            self.play(samples)
        }
    }

    func stop() {
        generation &+= 1
        tail?.cancel()
        tail = nil
        player.stop()
        if engine.isRunning { engine.stop() }
        queue.reset()
    }

    private func play(_ samples: [Float]) {
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
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }

        do {
            try startEngineIfNeeded()
        } catch {
            queue.finishedOne()
            return
        }

        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.queue.finishedOne() }
        }
        if !player.isPlaying { player.play() }
    }

    private func startEngineIfNeeded() throws {
        guard !engine.isRunning else { return }
        // The session is normally already configured by SpeechListener, but
        // Mira can speak before anyone has spoken to her.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat,
                                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        engine.prepare()
        try engine.start()
    }
}

/// Serializes access to the sherpa-onnx TTS handle, which is not thread-safe,
/// and keeps synthesis off the main thread.
actor KokoroSynthesizer {

    enum EngineError: LocalizedError {
        case filesMissing(String)
        case initializationFailed
        case audioFormatUnavailable

        var errorDescription: String? {
            switch self {
            case .filesMissing(let what):  return "The Kokoro voice is missing \(what)."
            case .initializationFailed:    return "The Kokoro voice couldn't be loaded."
            case .audioFormatUnavailable:  return "Couldn't open an audio output for the Kokoro voice."
            }
        }
    }

    private let tts: OpaquePointer
    nonisolated let sampleRate: Double

    init(directory: URL) throws {
        let model = directory.appendingPathComponent("model.int8.onnx")
        let voices = directory.appendingPathComponent("voices.bin")
        let tokens = directory.appendingPathComponent("tokens.txt")
        let espeak = directory.appendingPathComponent("espeak-ng-data")
        let lexicon = directory.appendingPathComponent("lexicon-us-en.txt")

        for (url, label) in [(model, "model.int8.onnx"), (voices, "voices.bin"),
                             (tokens, "tokens.txt"), (espeak, "espeak-ng-data")] {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw EngineError.filesMissing(label)
            }
        }
        // The lexicon only improves pronunciation; espeak-ng handles the rest.
        let lexiconPath = FileManager.default.fileExists(atPath: lexicon.path) ? lexicon.path : ""

        // The config holds borrowed C strings; they must outlive the create
        // call, so they're owned here and released once it returns.
        var owned: [UnsafeMutablePointer<CChar>] = []
        defer { owned.forEach { free($0) } }
        func cString(_ value: String) -> UnsafePointer<CChar>? {
            guard let copy = strdup(value) else { return nil }
            owned.append(copy)
            return UnsafePointer(copy)
        }

        var kokoro = SherpaOnnxOfflineTtsKokoroModelConfig()
        kokoro.model = cString(model.path)
        kokoro.voices = cString(voices.path)
        kokoro.tokens = cString(tokens.path)
        kokoro.data_dir = cString(espeak.path)
        kokoro.lexicon = cString(lexiconPath)
        kokoro.lang = cString("en-us")
        kokoro.length_scale = 1.0

        var modelConfig = SherpaOnnxOfflineTtsModelConfig()
        modelConfig.kokoro = kokoro
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
        sampleRate = rate > 0 ? Double(rate) : 24000
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
