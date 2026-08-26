import Foundation
import SherpaOnnxC

/// Streaming speech-to-text through sherpa-onnx, using the same framework the
/// Kokoro voice already links against.
///
/// Preferred over `SFSpeechRecognizer` for three reasons: it is genuinely
/// on-device rather than falling back to Apple's server recognizer when the
/// offline asset isn't installed; it doesn't need Dictation enabled; and it
/// emits a growing transcript continuously rather than in chunks, which is
/// what makes the live transcription read as live.
actor StreamingRecognizer {

    enum RecognizerError: LocalizedError {
        case filesMissing(String)
        case initializationFailed

        var errorDescription: String? {
            switch self {
            case .filesMissing(let what): return "The speech model is missing \(what)."
            case .initializationFailed:   return "The speech model couldn't be loaded."
            }
        }
    }

    private let recognizer: OpaquePointer
    private var stream: OpaquePointer?

    /// The model runs at 16 kHz; the caller resamples the microphone to match.
    nonisolated static let sampleRate: Double = 16000

    init(directory: URL) throws {
        let encoder = directory.appendingPathComponent("encoder.onnx")
        let decoder = directory.appendingPathComponent("decoder.onnx")
        let joiner = directory.appendingPathComponent("joiner.onnx")
        let tokens = directory.appendingPathComponent("tokens.txt")

        for (url, label) in [(encoder, "encoder.onnx"), (decoder, "decoder.onnx"),
                             (joiner, "joiner.onnx"), (tokens, "tokens.txt")] {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw RecognizerError.filesMissing(label)
            }
        }

        // Borrowed C strings must outlive the create call and no longer.
        var owned: [UnsafeMutablePointer<CChar>] = []
        defer { owned.forEach { free($0) } }
        func cString(_ value: String) -> UnsafePointer<CChar>? {
            guard let copy = strdup(value) else { return nil }
            owned.append(copy)
            return UnsafePointer(copy)
        }

        var transducer = SherpaOnnxOnlineTransducerModelConfig()
        transducer.encoder = cString(encoder.path)
        transducer.decoder = cString(decoder.path)
        transducer.joiner = cString(joiner.path)

        var model = SherpaOnnxOnlineModelConfig()
        model.transducer = transducer
        model.tokens = cString(tokens.path)
        model.provider = cString("cpu")
        model.model_type = cString("zipformer2")
        model.debug = 0
        // Leaves room for the language model, which is generating at the same
        // time on the other side of a turn.
        model.num_threads = Int32(max(1, min(2, ProcessInfo.processInfo.activeProcessorCount - 2)))

        var features = SherpaOnnxFeatureConfig()
        features.sample_rate = Int32(Self.sampleRate)
        features.feature_dim = 80

        var config = SherpaOnnxOnlineRecognizerConfig()
        config.feat_config = features
        config.model_config = model
        config.decoding_method = cString("greedy_search")
        config.max_active_paths = 4
        // sherpa-onnx detects the end of a turn itself, which is what replaces
        // the hand-rolled silence timer the Apple recognizer needed.
        config.enable_endpoint = 1
        config.rule1_min_trailing_silence = 2.4   // silence before any speech
        config.rule2_min_trailing_silence = 1.1   // silence after speech
        config.rule3_min_utterance_length = 25    // hard cap on one turn

        guard let handle = withUnsafePointer(to: &config, { SherpaOnnxCreateOnlineRecognizer($0) }) else {
            throw RecognizerError.initializationFailed
        }
        recognizer = handle
    }

    deinit {
        if let stream { SherpaOnnxDestroyOnlineStream(stream) }
        SherpaOnnxDestroyOnlineRecognizer(recognizer)
    }

    /// Begins a turn, discarding anything left from the last one.
    func beginTurn() {
        if let stream { SherpaOnnxDestroyOnlineStream(stream) }
        stream = SherpaOnnxCreateOnlineStream(recognizer)
    }

    func endTurn() {
        guard let stream else { return }
        SherpaOnnxDestroyOnlineStream(stream)
        self.stream = nil
    }

    struct Update {
        let text: String
        /// True once the recognizer decides the speaker has stopped.
        let isEndpoint: Bool
    }

    /// Feeds one buffer of 16 kHz mono float samples and returns the transcript
    /// so far. Returns nil when no turn is running.
    func accept(_ samples: [Float]) -> Update? {
        guard let stream else { return nil }

        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            SherpaOnnxOnlineStreamAcceptWaveform(stream, Int32(Self.sampleRate),
                                                 base, Int32(buffer.count))
        }
        while SherpaOnnxIsOnlineStreamReady(recognizer, stream) == 1 {
            SherpaOnnxDecodeOnlineStream(recognizer, stream)
        }

        var text = ""
        if let result = SherpaOnnxGetOnlineStreamResult(recognizer, stream) {
            if let raw = result.pointee.text { text = String(cString: raw) }
            SherpaOnnxDestroyOnlineRecognizerResult(result)
        }

        let ended = SherpaOnnxOnlineStreamIsEndpoint(recognizer, stream) == 1
        if ended {
            // Reset so the next utterance starts clean; the caller has the text.
            SherpaOnnxOnlineStreamReset(recognizer, stream)
        }
        return Update(text: text, isEndpoint: ended)
    }
}
