import Foundation
import AVFoundation
import CryptoKit

/// Microsoft Edge's read-aloud voices, over the same endpoint the browser uses.
///
/// This is not a public API. It is the undocumented endpoint behind Edge's
/// Read Aloud, reached with a hardcoded client token, and Microsoft has changed
/// its authentication before in ways that broke every client overnight. It is
/// also a network service, so Mira cannot speak with it in airplane mode.
/// Both of which is why a failure here permanently drops to the on-device
/// voice for the rest of the session rather than going quiet.
enum EdgeSpeech {

    private static let trustedToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private static let gecVersion = "1-130.0.2849.68"
    private static let userAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0"
    private static let origin = "chrome-extension://jdiccldimpahbcfhpmforloilhcmeaii"

    struct Voice: Codable, Identifiable, Hashable {
        let ShortName: String
        let FriendlyName: String
        let Locale: String
        let Gender: String

        var id: String { ShortName }

        /// "Rosa" out of "Microsoft Rosa Online (Natural) - English (United States)".
        var displayName: String {
            if let name = ShortName.split(separator: "-").last {
                return String(name).replacingOccurrences(of: "Neural", with: "")
            }
            return ShortName
        }
    }

    enum EdgeError: LocalizedError {
        case badResponse(Int)
        case noAudio
        case socketFailed(String)

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "Microsoft's voice service refused the request (\(code))."
            case .noAudio:               return "Microsoft's voice service returned no audio."
            case .socketFailed(let why): return "Couldn't reach Microsoft's voice service: \(why)"
            }
        }
    }

    /// Edge requires a token derived from the clock, rounded to a five-minute
    /// window, hashed together with the client token. Without it the service
    /// answers 403.
    static func securityToken(now: Date = Date()) -> String {
        // Windows file time: 100-nanosecond ticks since 1601.
        var seconds = (now.timeIntervalSince1970 + 11_644_473_600).rounded(.down)
        seconds -= seconds.truncatingRemainder(dividingBy: 300)
        let ticks = UInt64(seconds) * 10_000_000
        let digest = SHA256.hash(data: Data("\(ticks)\(trustedToken)".utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    private static func decorate(_ request: inout URLRequest) {
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    }

    // MARK: - Voice list

    static func voices() async throws -> [Voice] {
        var components = URLComponents(
            string: "https://speech.platform.bing.com/consumer/speech/synthesize/readaloud/voices/list")!
        components.queryItems = [
            .init(name: "trustedclienttoken", value: trustedToken),
            .init(name: "Sec-MS-GEC", value: securityToken()),
            .init(name: "Sec-MS-GEC-Version", value: gecVersion)
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        decorate(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw EdgeError.badResponse(http.statusCode)
        }
        return try JSONDecoder().decode([Voice].self, from: data)
    }

    /// Picks the voice the app should use, preferring one called Rosa.
    ///
    /// The name is resolved against the live list rather than hardcoded: I
    /// could not reach Microsoft's voice list to confirm a Rosa exists, so the
    /// app checks on the device and falls back to a known English voice.
    static func resolveVoice(preferring wanted: String) async -> String {
        guard let list = try? await voices(), !list.isEmpty else { return "en-US-AriaNeural" }
        let english = list.filter { $0.Locale.hasPrefix("en") }
        let match = english.first { $0.ShortName.localizedCaseInsensitiveContains(wanted) }
            ?? list.first { $0.ShortName.localizedCaseInsensitiveContains(wanted) }
            ?? english.first { $0.FriendlyName.localizedCaseInsensitiveContains(wanted) }
        return match?.ShortName
            ?? english.first(where: { $0.Locale == "en-US" })?.ShortName
            ?? english.first?.ShortName
            ?? "en-US-AriaNeural"
    }

    // MARK: - Synthesis

    /// Returns MP3 bytes for one sentence.
    static func synthesize(_ text: String, voice: String, ratePercent: Int) async throws -> Data {
        var components = URLComponents(
            string: "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1")!
        components.queryItems = [
            .init(name: "TrustedClientToken", value: trustedToken),
            .init(name: "Sec-MS-GEC", value: securityToken()),
            .init(name: "Sec-MS-GEC-Version", value: gecVersion)
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        decorate(&request)

        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: request)
        socket.resume()
        defer {
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
        }

        let stamp = ISO8601DateFormatter().string(from: Date())
        let config = """
        X-Timestamp:\(stamp)\r\n\
        Content-Type:application/json; charset=utf-8\r\n\
        Path:speech.config\r\n\r\n\
        {"context":{"synthesis":{"audio":{"metadataoptions":\
        {"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},\
        "outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}
        """
        let ssml = """
        X-RequestId:\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))\r\n\
        Content-Type:application/ssml+xml\r\n\
        X-Timestamp:\(stamp)Z\r\n\
        Path:ssml\r\n\r\n\
        <speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>\
        <voice name='\(voice)'>\
        <prosody rate='\(ratePercent >= 0 ? "+" : "")\(ratePercent)%' pitch='+0Hz'>\
        \(escape(text))\
        </prosody></voice></speak>
        """

        do {
            try await socket.send(.string(config))
            try await socket.send(.string(ssml))
        } catch {
            throw EdgeError.socketFailed(error.localizedDescription)
        }

        var audio = Data()
        // Bounded so a service that never sends turn.end cannot hang a turn.
        for _ in 0..<4096 {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await socket.receive()
            } catch {
                if audio.isEmpty { throw EdgeError.socketFailed(error.localizedDescription) }
                break
            }
            switch message {
            case .string(let text):
                if text.contains("Path:turn.end") {
                    guard !audio.isEmpty else { throw EdgeError.noAudio }
                    return audio
                }
            case .data(let frame):
                // Each binary frame is a two-byte big-endian header length,
                // that many header bytes, then the audio. Sliced rather than
                // subscripted: a Data slice does not have to be 0-based.
                guard frame.count > 2 else { continue }
                let lead = [UInt8](frame.prefix(2))
                let start = 2 + (Int(lead[0]) << 8 | Int(lead[1]))
                guard frame.count > start else { continue }
                audio.append(Data(frame.dropFirst(start)))
            @unknown default:
                continue
            }
        }
        guard !audio.isEmpty else { throw EdgeError.noAudio }
        return audio
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Speaks through Edge, falling back permanently to the on-device voice the
/// first time the service is unreachable.
@MainActor
final class EdgeVoice: NSObject, VoiceOutput, AVAudioPlayerDelegate {

    private let queue = SpeechQueueState()
    private let fallback: any VoiceOutput

    private var degraded = false
    private var expectingMore = false
    private var finishedCallback: (() -> Void)?

    private var player: AVAudioPlayer?
    private var playbackFinished: CheckedContinuation<Void, Never>?
    private var tail: Task<Void, Never>?
    private var generation = 0

    /// Resolved once, then remembered, so every sentence isn't a list fetch.
    private var voiceName: String?

    /// Called when Edge fails and the on-device voice takes over.
    var onDegraded: ((String) -> Void)?

    init(fallback: any VoiceOutput) {
        self.fallback = fallback
        super.init()
    }

    var onFinishedSpeaking: (() -> Void)? {
        get { finishedCallback }
        set {
            finishedCallback = newValue
            if degraded { fallback.onFinishedSpeaking = newValue } else { queue.onDrained = newValue }
        }
    }

    var describedVoice: String {
        if degraded { return fallback.describedVoice + " (Edge unavailable)" }
        let name = voiceName ?? UserDefaults.standard.string(forKey: Prefs.edgeVoiceKey) ?? "Rosa"
        return "Edge · \(name.split(separator: "-").last.map(String.init) ?? name)"
    }

    func setExpectingMore(_ expecting: Bool) {
        expectingMore = expecting
        if degraded { fallback.setExpectingMore(expecting) } else { queue.setExpectingMore(expecting) }
    }

    func enqueue(_ sentence: String) {
        if degraded { fallback.enqueue(sentence); return }
        let spoken = SpeechText.forSpeaking(sentence)
        guard !spoken.isEmpty else { return }
        queue.added()

        let previous = tail
        let token = generation
        tail = Task { [weak self] in
            _ = await previous?.value
            guard let self, !Task.isCancelled, self.generation == token else { return }
            do {
                let voice = await self.currentVoice()
                let data = try await EdgeSpeech.synthesize(spoken, voice: voice,
                                                           ratePercent: Self.ratePercent)
                guard !Task.isCancelled, self.generation == token else { return }
                await self.play(data)
                self.queue.finishedOne()
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                self.degrade(reason: error.localizedDescription)
                self.fallback.enqueue(sentence)
            }
        }
    }

    func stop() {
        generation &+= 1
        tail?.cancel()
        tail = nil
        player?.stop()
        player = nil
        resumePlayback()
        queue.reset()
        fallback.stop()
    }

    // MARK: - Internals

    private func currentVoice() async -> String {
        if let voiceName { return voiceName }
        let stored = UserDefaults.standard.string(forKey: Prefs.edgeVoiceKey) ?? ""
        if !stored.isEmpty, stored.contains("-") {
            voiceName = stored
            return stored
        }
        // Resolve the friendly name the user asked for against the live list.
        let resolved = await EdgeSpeech.resolveVoice(preferring: stored.isEmpty ? "Rosa" : stored)
        UserDefaults.standard.set(resolved, forKey: Prefs.edgeVoiceKey)
        voiceName = resolved
        return resolved
    }

    private static var ratePercent: Int {
        let stored = UserDefaults.standard.double(forKey: Prefs.speedKey)
        let speed = stored > 0 ? stored : 1.0
        return Int(((speed - 1) * 100).rounded())
    }

    /// Once Edge has failed, the on-device voice owns the turn's bookkeeping —
    /// otherwise this queue would drain and hand the microphone back while the
    /// fallback was still speaking.
    private func degrade(reason: String) {
        guard !degraded else { return }
        degraded = true
        queue.onDrained = nil
        queue.reset()
        fallback.onFinishedSpeaking = finishedCallback
        fallback.setExpectingMore(expectingMore)
        onDegraded?(reason)
    }

    private func play(_ data: Data) async {
        do {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playAndRecord, mode: .voiceChat,
                                     options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try? session.setActive(true, options: .notifyOthersOnDeactivation)

            let audio = try AVAudioPlayer(data: data)
            audio.delegate = self
            player = audio
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                playbackFinished = continuation
                if !audio.play() { resumePlayback() }
            }
        } catch {
            resumePlayback()
        }
    }

    /// Safe to call twice; a continuation resumed twice would trap.
    private func resumePlayback() {
        playbackFinished?.resume()
        playbackFinished = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.resumePlayback() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.resumePlayback() }
    }
}
