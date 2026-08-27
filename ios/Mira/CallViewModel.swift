import Foundation
import SwiftUI
import UIKit

/// Drives the call: listen → generate → speak → listen again.
@MainActor
final class CallViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case loading(String)
        case listening
        case thinking
        case speaking
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript: [ChatMessage] = []
    @Published private(set) var liveMiraText = ""
    @Published private(set) var modelDescription = ""
    @Published var handsFree = true {
        didSet { UserDefaults.standard.set(handsFree, forKey: Prefs.handsFreeKey) }
    }

    let listener = SpeechListener()
    /// Every conversation is saved so the Chats tab can scroll back through them.
    let sessions = SessionStore()
    /// Edge when it's selected and reachable, otherwise the on-device voice.
    @Published private(set) var speaker: any VoiceOutput

    /// Set when Edge drops out mid-conversation, so the UI can say so.
    @Published private(set) var voiceNotice: String?

    private var engine: LlamaEngine?
    private var chat: MDLOFile.ChatConfig?
    private var generation: Task<Void, Never>?

    /// The conversation being recorded. Cleared by `reset()`, so starting a
    /// new chat starts a new entry rather than extending the last one.
    private var activeSession: ChatSession?

    /// Conversation turns kept in the prompt. Older turns fall off so the
    /// context window never overflows mid-call.
    private let maxTurns = 16

    init() {
        if UserDefaults.standard.object(forKey: Prefs.handsFreeKey) != nil {
            handsFree = UserDefaults.standard.bool(forKey: Prefs.handsFreeKey)
        }
        speaker = Self.makeSpeaker()
        wireSpeaker()
    }

    /// Edge is the default; the on-device voice sits behind it as the fallback,
    /// so a dead connection degrades rather than silences her.
    private static func makeSpeaker() -> any VoiceOutput {
        let local: any VoiceOutput = KokoroVoice.makeIfAvailable() ?? Speaker()
        let engine = UserDefaults.standard.string(forKey: Prefs.engineKey) ?? "edge"
        return engine == "edge" ? EdgeVoice(fallback: local) : local
    }

    private func wireSpeaker() {
        speaker.onFinishedSpeaking = { [weak self] in
            guard let self, self.phase == .speaking else { return }
            if self.handsFree { self.beginListening() } else { self.phase = .idle }
        }
        (speaker as? EdgeVoice)?.onDegraded = { [weak self] reason in
            self?.voiceNotice = "On-device voice — \(reason)"
        }
    }

    /// Rebuilds the voice after the engine is changed in Settings.
    func applyVoiceEngine() {
        speaker.stop()
        voiceNotice = nil
        speaker = Self.makeSpeaker()
        wireSpeaker()
    }

    /// True when nothing Mira says leaves the phone.
    var isFullyLocal: Bool { !(speaker is EdgeVoice) }

    // MARK: - Setup

    func reportFailure(_ message: String) {
        phase = .failed(message)
    }

    func load(modelURL: URL) {
        generation?.cancel()
        listener.stop()
        speaker.stop()
        phase = .loading("Opening Mira…")

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                // The first extraction verifies the checksum; later launches
                // reuse the cached GGUF and skip hashing ~250 MB.
                let file = try ModelReader.load(from: modelURL)
                await MainActor.run { self?.phase = .loading("Warming up…") }
                let engine = try LlamaEngine(modelURL: file.modelURL)
                await MainActor.run {
                    guard let self else { return }
                    self.engine = engine
                    self.chat = file.chat
                    self.transcript = [ChatMessage(role: .system, text: file.chat.systemPrompt)]
                    self.modelDescription = file.summary
                    self.phase = .idle
                }
            } catch {
                await MainActor.run {
                    self?.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Turn taking

    func beginListening() {
        guard engine != nil else { return }
        speaker.stop()
        do {
            try listener.start { [weak self] outcome in
                Task { @MainActor in
                    guard let self else { return }
                    switch outcome {
                    case .heard(let text):
                        self.send(text)
                    case .silence:
                        // Nothing said. Hand the button back quietly rather
                        // than sitting on "Listening…".
                        self.phase = .idle
                    case .failed(let reason):
                        self.phase = .failed(reason)
                    }
                }
            }
            phase = .listening
            tap(.light)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Tapping while Mira talks cuts her off — normal phone-call behavior.
    func interrupt() {
        generation?.cancel()
        generation = nil
        speaker.stop()
        beginListening()
    }

    func endCall() {
        generation?.cancel()
        generation = nil
        listener.stop()
        speaker.stop()
        liveMiraText = ""
        phase = .idle
    }

    func reset() {
        endCall()
        if let systemPrompt = chat?.systemPrompt {
            transcript = [ChatMessage(role: .system, text: systemPrompt)]
        }
        liveMiraText = ""
        activeSession = nil
    }

    /// Speaks Mira's last reply again, without asking the model for anything.
    var canReplay: Bool {
        transcript.last(where: { $0.role == .assistant }) != nil
    }

    func replayLastReply() {
        guard let reply = transcript.last(where: { $0.role == .assistant }) else { return }
        generation?.cancel()
        generation = nil
        listener.stop()
        speaker.stop()
        phase = .speaking
        speaker.setExpectingMore(true)
        for sentence in SpeechText.sentences(from: reply.text + " ").complete {
            speaker.enqueue(sentence)
        }
        speaker.setExpectingMore(false)
    }

    /// Asks again with the same question — for when the reply was cut off or
    /// the model wandered.
    var canRetry: Bool {
        transcript.last(where: { $0.role == .user }) != nil
    }

    func retryLastTurn() {
        guard let question = transcript.last(where: { $0.role == .user })?.text else { return }
        generation?.cancel()
        generation = nil
        speaker.stop()
        // Drop the previous exchange so the model isn't answering itself.
        if transcript.last?.role == .assistant { transcript.removeLast() }
        if transcript.last?.role == .user { transcript.removeLast() }
        send(question)
    }

    /// Picks a saved conversation back up: its turns become the live
    /// transcript and the prompt, and new turns extend that same entry.
    func resume(_ session: ChatSession) {
        guard let chat else { return }
        endCall()
        transcript = [ChatMessage(role: .system, text: chat.systemPrompt)]
            + session.messages.map {
                ChatMessage(role: $0.isMira ? .assistant : .user, text: $0.text)
            }
        trimHistory()
        activeSession = session
        liveMiraText = ""
        phase = .idle
    }

    /// Appends to the saved conversation, creating one on the first turn.
    private func remember(_ text: String, isMira: Bool) {
        var session = activeSession
            ?? ChatSession(id: UUID(), startedAt: Date(), endedAt: nil, messages: [])
        session.messages.append(ChatSession.Turn(isMira: isMira, text: text))
        session.endedAt = Date()
        activeSession = session
        sessions.record(session)
    }

    func send(_ text: String) {
        guard let engine, let chat else { return }
        listener.stop()

        tap(.soft)
        transcript.append(ChatMessage(role: .user, text: text))
        remember(text, isMira: false)
        trimHistory()
        liveMiraText = ""
        phase = .thinking

        let messages = transcript
        // Held open until the last sentence is queued, so the pause between
        // two sentences isn't mistaken for the end of Mira's turn.
        speaker.setExpectingMore(true)

        generation = Task { [weak self] in
            guard let self else { return }
            var buffer = ""
            var spokenAnything = false

            do {
                let stream = await engine.generate(messages: messages,
                                                   temperature: Float(chat.temperature),
                                                   topP: Float(chat.topP),
                                                   maxTokens: chat.maxReplyTokens)
                for try await piece in stream {
                    if Task.isCancelled { break }
                    buffer += piece

                    // Speak each sentence as soon as it's complete, so speech
                    // overlaps generation instead of waiting for the full reply.
                    let (complete, remainder) = SpeechText.sentences(from: buffer)
                    if !complete.isEmpty {
                        for sentence in complete {
                            self.speaker.enqueue(sentence)
                            spokenAnything = true
                        }
                        self.liveMiraText += complete.joined(separator: " ") + " "
                        self.phase = .speaking
                        buffer = remainder
                    }
                }

                // An interrupted reply is already handled by `interrupt()`:
                // the speaker is stopped and the microphone is live again.
                guard !Task.isCancelled else {
                    self.speaker.setExpectingMore(false)
                    return
                }

                let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty {
                    self.speaker.enqueue(tail)
                    self.liveMiraText += tail
                    spokenAnything = true
                    self.phase = .speaking
                }

                let reply = self.liveMiraText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !reply.isEmpty {
                    self.transcript.append(ChatMessage(role: .assistant, text: reply))
                    self.remember(reply, isMira: true)
                }
                self.liveMiraText = ""
                if !spokenAnything { self.phase = .idle }
                // Releases the turn: once the queue drains, Mira hands back.
                self.speaker.setExpectingMore(false)
            } catch {
                self.speaker.setExpectingMore(false)
                if !Task.isCancelled {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// A short tick when a turn starts or ends. Off if the user turned
    /// haptics off in Settings.
    private func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let defaults = UserDefaults.standard
        let wanted = defaults.object(forKey: Prefs.hapticsKey) == nil
            ? true : defaults.bool(forKey: Prefs.hapticsKey)
        guard wanted else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// Keeps the system prompt plus the most recent turns.
    private func trimHistory() {
        guard transcript.count > maxTurns * 2 + 1 else { return }
        let system = transcript.first
        let recent = transcript.suffix(maxTurns * 2)
        transcript = ([system].compactMap { $0 }) + recent
    }
}
