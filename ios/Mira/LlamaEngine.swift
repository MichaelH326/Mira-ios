import Foundation
import llama

/// Thin async wrapper over llama.cpp for on-device generation.
///
/// Generation is streamed token by token so the caller can speak each
/// sentence while the next one is still being produced — the same trick
/// `voice/run_mira.py` uses to keep the conversation feeling live.
actor LlamaEngine {

    enum EngineError: LocalizedError {
        case modelLoadFailed
        case contextFailed
        case tokenizationFailed

        var errorDescription: String? {
            switch self {
            case .modelLoadFailed:    return "Mira's model couldn't be loaded."
            case .contextFailed:      return "Couldn't start the model — try restarting the app."
            case .tokenizationFailed: return "Couldn't process that message."
            }
        }
    }

    private let model: OpaquePointer
    private let context: OpaquePointer
    private let contextTokens: Int32

    init(modelURL: URL, contextTokens: Int32 = 2048) throws {
        self.contextTokens = contextTokens

        llama_backend_init()

        var modelParams = llama_model_default_params()
        // These small quantized models run fine on CPU, and CPU keeps memory
        // predictable — Metal offload buys little and costs headroom.
        modelParams.n_gpu_layers = 0

        guard let loaded = llama_model_load_from_file(modelURL.path, modelParams) else {
            throw EngineError.modelLoadFailed
        }
        self.model = loaded

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(contextTokens)
        ctxParams.n_batch = 512
        ctxParams.n_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount - 2))
        ctxParams.n_threads_batch = ctxParams.n_threads

        guard let ctx = llama_init_from_model(loaded, ctxParams) else {
            llama_model_free(loaded)
            throw EngineError.contextFailed
        }
        self.context = ctx
    }

    deinit {
        llama_free(context)
        llama_model_free(model)
        llama_backend_free()
    }

    private func makeSampler(temperature: Float, topP: Float) -> UnsafeMutablePointer<llama_sampler> {
        var params = llama_sampler_chain_default_params()
        params.no_perf = true
        let chain = llama_sampler_chain_init(params)
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(topP, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(temperature))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(LLAMA_DEFAULT_SEED))
        return chain!
    }

    /// Applies the chat template baked into the GGUF, so we don't hardcode
    /// one model's prompt format. Models without a template fall back to a
    /// plain transcript, which is enough for the small chat models we ship.
    private func renderPrompt(messages: [ChatMessage]) -> String {
        var buffers: [UnsafeMutablePointer<CChar>] = []
        defer { buffers.forEach { free($0) } }

        var cMessages: [llama_chat_message] = []
        for message in messages {
            guard let role = strdup(message.role.rawValue),
                  let content = strdup(message.text) else { continue }
            buffers.append(role)
            buffers.append(content)
            cMessages.append(llama_chat_message(role: role, content: content))
        }

        guard let template = llama_model_chat_template(model, nil) else {
            return fallbackPrompt(messages: messages)
        }

        // Ask once with a generous buffer; if the model needs more, the call
        // returns the required size and we retry exactly once.
        let messageCount = cMessages.count
        var capacity = 32768
        var out = [CChar](repeating: 0, count: capacity)
        var written = llama_chat_apply_template(template, &cMessages, messageCount,
                                                true, &out, Int32(capacity))
        if written > Int32(capacity) {
            capacity = Int(written) + 1
            out = [CChar](repeating: 0, count: capacity)
            written = llama_chat_apply_template(template, &cMessages, messageCount,
                                                true, &out, Int32(capacity))
        }
        guard written > 0, written <= Int32(capacity) else {
            return fallbackPrompt(messages: messages)
        }

        let bytes = out.prefix(Int(written)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func fallbackPrompt(messages: [ChatMessage]) -> String {
        var lines: [String] = []
        for message in messages {
            switch message.role {
            case .system:    lines.append(message.text)
            case .user:      lines.append("User: \(message.text)")
            case .assistant: lines.append("Mira: \(message.text)")
            }
        }
        lines.append("Mira:")
        return lines.joined(separator: "\n")
    }

    /// Streams generated text. The continuation finishes when the model emits
    /// an end-of-generation token, hits `maxTokens`, or the task is cancelled.
    func generate(messages: [ChatMessage],
                  temperature: Float,
                  topP: Float,
                  maxTokens: Int) -> AsyncThrowingStream<String, Error> {

        AsyncThrowingStream { continuation in
            Task {
                let vocab = llama_model_get_vocab(model)

                let prompt = renderPrompt(messages: messages)
                guard !prompt.isEmpty else {
                    continuation.finish(throwing: EngineError.tokenizationFailed)
                    return
                }

                // Tokenize
                let utf8Count = prompt.utf8.count
                let tokenCapacity = utf8Count + 16
                var tokens = [llama_token](repeating: 0, count: tokenCapacity)
                let count = llama_tokenize(vocab, prompt, Int32(utf8Count),
                                           &tokens, Int32(tokenCapacity), true, true)
                guard count > 0 else {
                    continuation.finish(throwing: EngineError.tokenizationFailed)
                    return
                }
                tokens = Array(tokens.prefix(Int(count)))

                // Keep the newest tokens if history outgrew the window.
                let room = Int(contextTokens) - maxTokens - 8
                if room > 0, tokens.count > room {
                    tokens = Array(tokens.suffix(room))
                }

                llama_memory_clear(llama_get_memory(context), true)

                var batch = llama_batch_init(Int32(max(tokens.count, 1)), 0, 1)
                defer { llama_batch_free(batch) }

                func add(_ token: llama_token, position: Int32, logits: Bool) {
                    batch.token[Int(batch.n_tokens)] = token
                    batch.pos[Int(batch.n_tokens)] = position
                    batch.n_seq_id[Int(batch.n_tokens)] = 1
                    batch.seq_id[Int(batch.n_tokens)]![0] = 0
                    batch.logits[Int(batch.n_tokens)] = logits ? 1 : 0
                    batch.n_tokens += 1
                }

                batch.n_tokens = 0
                for (index, token) in tokens.enumerated() {
                    add(token, position: Int32(index), logits: index == tokens.count - 1)
                }
                guard llama_decode(context, batch) == 0 else {
                    continuation.finish(throwing: EngineError.contextFailed)
                    return
                }

                let chain = makeSampler(temperature: temperature, topP: topP)
                defer { llama_sampler_free(chain) }

                var position = Int32(tokens.count)
                var produced = 0
                let pieceCapacity = 256
                var piece = [CChar](repeating: 0, count: pieceCapacity)
                // A single token can be part of a multi-byte character, so bytes
                // are held back until they decode as valid UTF-8.
                var undecoded = [UInt8]()

                while produced < maxTokens {
                    if Task.isCancelled { break }

                    let next = llama_sampler_sample(chain, context, -1)
                    if llama_vocab_is_eog(vocab, next) { break }

                    let length = llama_token_to_piece(vocab, next, &piece,
                                                      Int32(pieceCapacity), 0, true)
                    if length > 0 {
                        undecoded.append(contentsOf: piece.prefix(Int(length))
                            .map { UInt8(bitPattern: $0) })
                        if let text = String(bytes: undecoded, encoding: .utf8) {
                            undecoded.removeAll(keepingCapacity: true)
                            continuation.yield(text)
                        }
                    }

                    batch.n_tokens = 0
                    add(next, position: position, logits: true)
                    guard llama_decode(context, batch) == 0 else { break }

                    position += 1
                    produced += 1
                }

                // Anything still undecoded is a truncated character; drop it
                // rather than emitting replacement glyphs into speech.
                continuation.finish()
            }
        }
    }
}

struct ChatMessage: Identifiable, Equatable {
    enum Role: String { case system, user, assistant }

    let id = UUID()
    let role: Role
    var text: String
}
