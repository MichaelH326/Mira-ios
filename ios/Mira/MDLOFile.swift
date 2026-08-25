import Foundation
import CryptoKit

/// Parses the `.mdlo` v2 container produced by `voice/package_mdlo.py`.
///
/// Byte layout:
///   0..<4    magic  "MDLO"
///   4..<8    version           UInt32, little endian (2)
///   8..<16   headerLength      UInt64, little endian
///   16..<16+headerLength       UTF-8 JSON header
///   rest                       a complete GGUF file
///
/// The GGUF payload is extracted once into Application Support and reused,
/// because llama.cpp memory-maps the model from disk.
struct MDLOFile {

    struct ChatConfig: Decodable {
        let systemPrompt: String
        let temperature: Double
        let topP: Double
        let maxReplyTokens: Int

        enum CodingKeys: String, CodingKey {
            case systemPrompt = "system_prompt"
            case temperature
            case topP = "top_p"
            case maxReplyTokens = "max_reply_tokens"
        }
    }

    struct Provenance: Decodable {
        let baseModel: String?
        let quantization: String?
        let finetuneSteps: Int?

        enum CodingKeys: String, CodingKey {
            case baseModel = "base_model"
            case quantization
            case finetuneSteps = "finetune_steps"
        }
    }

    struct Header: Decodable {
        let format: String
        let formatVersion: Int
        let modelName: String
        let engine: String
        let payloadSha256: String
        let payloadBytes: Int
        let chat: ChatConfig
        let provenance: Provenance?

        enum CodingKeys: String, CodingKey {
            case format
            case formatVersion = "format_version"
            case modelName = "model_name"
            case engine
            case payloadSha256 = "payload_sha256"
            case payloadBytes = "payload_bytes"
            case chat, provenance
        }
    }

    enum LoadError: LocalizedError {
        case notMDLO
        case unsupportedVersion(Int)
        case truncated
        case badHeader(String)
        case checksumMismatch
        case unsupportedEngine(String)

        var errorDescription: String? {
            switch self {
            case .notMDLO:                  return "That file isn't an MDLO model."
            case .unsupportedVersion(let v): return "MDLO version \(v) isn't supported by this app (needs version 2)."
            case .truncated:                return "The model file is incomplete — try downloading it again."
            case .badHeader(let why):       return "The model header couldn't be read: \(why)"
            case .checksumMismatch:         return "The model file is corrupt — try downloading it again."
            case .unsupportedEngine(let e): return "This model uses the '\(e)' engine, which this app can't run."
            }
        }
    }

    let header: Header
    /// On-disk GGUF, ready to hand to llama.cpp.
    let modelURL: URL

    private static let magic = Data("MDLO".utf8)

    /// Reads `url`, verifies it, and materializes the GGUF payload on disk.
    /// - Parameter verifyChecksum: hashing ~250 MB takes a second or two; skip
    ///   on subsequent launches where the cached GGUF is already validated.
    static func load(from url: URL, verifyChecksum: Bool = true) throws -> MDLOFile {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        guard let prefix = try handle.read(upToCount: 16), prefix.count == 16 else {
            throw LoadError.truncated
        }
        guard prefix.prefix(4) == magic else { throw LoadError.notMDLO }

        let version = prefix.subdata(in: 4..<8).withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))
        }
        guard version == 2 else { throw LoadError.unsupportedVersion(Int(version)) }

        let headerLength = prefix.subdata(in: 8..<16).withUnsafeBytes {
            UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self))
        }
        guard headerLength > 0, headerLength < 8_000_000 else {
            throw LoadError.badHeader("implausible header length \(headerLength)")
        }
        guard let headerData = try handle.read(upToCount: Int(headerLength)),
              headerData.count == Int(headerLength) else {
            throw LoadError.truncated
        }

        let header: Header
        do {
            header = try JSONDecoder().decode(Header.self, from: headerData)
        } catch {
            throw LoadError.badHeader(error.localizedDescription)
        }
        guard header.engine == "gguf" else { throw LoadError.unsupportedEngine(header.engine) }

        // Cache the GGUF keyed by content hash: same model reuses it instantly.
        let cacheDir = try FileManager.default.url(for: .applicationSupportDirectory,
                                                   in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
            .appendingPathComponent("MiraModels", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cached = cacheDir.appendingPathComponent(String(header.payloadSha256.prefix(16)) + ".gguf")

        let existingSize = (try? FileManager.default
            .attributesOfItem(atPath: cached.path))?[.size] as? Int
        if existingSize != header.payloadBytes {
            try extractPayload(from: handle,
                               startingAt: 16 + Int(headerLength),
                               expecting: header,
                               to: cached,
                               verifyChecksum: verifyChecksum)
        }

        return MDLOFile(header: header, modelURL: cached)
    }

    /// Streams the payload to disk in chunks so a 250 MB model never sits in RAM twice.
    private static func extractPayload(from handle: FileHandle,
                                       startingAt offset: Int,
                                       expecting header: Header,
                                       to destination: URL,
                                       verifyChecksum: Bool) throws {
        try handle.seek(toOffset: UInt64(offset))

        let tmp = destination.appendingPathExtension("tmp")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        let out = try FileHandle(forWritingTo: tmp)
        var closed = false
        defer { if !closed { try? out.close() } }

        var hasher = SHA256()
        var written = 0
        let chunkSize = 4 * 1024 * 1024

        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            if verifyChecksum { hasher.update(data: chunk) }
            try out.write(contentsOf: chunk)
            written += chunk.count
        }
        try out.close()
        closed = true

        guard written == header.payloadBytes else {
            try? FileManager.default.removeItem(at: tmp)
            throw LoadError.truncated
        }
        if verifyChecksum {
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard digest == header.payloadSha256 else {
                try? FileManager.default.removeItem(at: tmp)
                throw LoadError.checksumMismatch
            }
        }

        // `replaceItemAt` needs an existing original, which isn't the case on
        // the first extraction — move into place instead, replacing a stale or
        // half-written cache if one is there.
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tmp, to: destination)

        // Model files shouldn't be uploaded to iCloud.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var dest = destination
        try? dest.setResourceValues(values)
    }
}
