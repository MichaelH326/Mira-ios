import Foundation

/// A model ready to hand to llama.cpp, however it arrived.
struct LoadedModel {
    /// GGUF on disk.
    let modelURL: URL
    let chat: MDLOFile.ChatConfig
    /// Shown in the header and in Settings, e.g. "mira · Q8_0".
    let summary: String
}

/// Opens either a `.mdlo` container or a plain GGUF file.
///
/// The container carries a system prompt and sampling settings alongside the
/// weights; a bare GGUF carries only weights, so it gets sensible defaults.
/// Both are common — GGUF is what every quantiser emits — and rejecting one
/// of them was just an obstacle.
enum ModelReader {

    enum ReadError: LocalizedError {
        case unreadable
        case unrecognized(String)

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "That file couldn't be read. It may still be downloading from iCloud."
            case .unrecognized(let marker):
                return "That isn't a model file — Mira reads .gguf and .mdlo, and this one starts with \(marker)."
            }
        }
    }

    private static let ggufMagic = Data([0x47, 0x47, 0x55, 0x46])   // "GGUF"
    private static let mdloMagic = Data("MDLO".utf8)

    static func load(from url: URL, verifyChecksum: Bool = true) throws -> LoadedModel {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let magic = try? handle.read(upToCount: 4), magic.count == 4 else {
            throw ReadError.unreadable
        }
        try? handle.close()

        if magic == mdloMagic {
            let file = try MDLOFile.load(from: url, verifyChecksum: verifyChecksum)
            let base = file.header.provenance?.baseModel ?? file.header.modelName
            let quant = file.header.provenance?.quantization
            return LoadedModel(modelURL: file.modelURL,
                               chat: file.header.chat,
                               summary: quant.map { "\(base) · \($0)" } ?? base)
        }

        if magic == ggufMagic {
            // Nothing to unpack: llama.cpp memory-maps a GGUF straight off
            // disk, so this also avoids the container's second copy.
            return LoadedModel(modelURL: url,
                               chat: defaultChat,
                               summary: describe(url))
        }

        throw ReadError.unrecognized(printable(magic))
    }

    /// What a bare GGUF gets, since it carries no prompt or sampling settings.
    static let defaultChat = MDLOFile.ChatConfig(
        systemPrompt: """
        You are Mira, a warm, concise voice assistant running entirely on this \
        phone. You are speaking out loud, so keep replies short and \
        conversational — a sentence or two unless more is asked for. Write \
        numbers as words. Never use lists, markdown, or emoji.
        """,
        temperature: 0.7,
        topP: 0.9,
        maxReplyTokens: 220
    )

    /// Pulls a quantisation tag out of the filename — "mira-Q8_0.gguf" reads
    /// as "mira · Q8_0". Only the name; the weights aren't inspected.
    static func describe(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        guard let range = name.range(of: #"[Qq]\d+(_[0-9A-Za-z]+)*"#,
                                     options: .regularExpression) else {
            return name
        }
        let quant = String(name[range]).uppercased()
        let base = name.replacingCharacters(in: range, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_. "))
        return base.isEmpty ? quant : "\(base) · \(quant)"
    }

    private static func printable(_ magic: Data) -> String {
        let text = String(decoding: magic, as: UTF8.self)
        let readable = text.allSatisfy { $0.isLetter || $0.isNumber }
        return readable ? "\"\(text)\"" : magic.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
