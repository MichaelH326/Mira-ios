import Foundation
import UniformTypeIdentifiers

/// Decides which model the app should run — `.gguf` or `.mdlo`.
///
/// Priority:
///   1. A model shipped inside the app bundle (`mira.gguf` or `mira.mdlo`)
///   2. A model the user imported previously, kept in Documents under its
///      own filename so several can sit side by side in Files
///
/// Bundling means the app works the moment it launches — no file picker, no
/// setup. Importing stays available so you can swap in a newer model without
/// rebuilding.
enum ModelLocator {

    enum Source: Equatable {
        case bundled(URL)
        case imported(URL)

        var url: URL {
            switch self {
            case .bundled(let url), .imported(let url): return url
            }
        }

        var isBundled: Bool {
            if case .bundled = self { return true }
            return false
        }
    }

    /// A model the user imported takes precedence only if it's *newer* than the
    /// bundled one, so shipping an updated app doesn't get shadowed by a stale
    /// import — but a deliberate import after installing still wins.
    static func current() -> Source? {
        let bundled = bundledModel()
        let imported = importedModel()

        switch (bundled, imported) {
        case (let bundled?, let imported?):
            let bundledDate = modificationDate(bundled) ?? .distantPast
            let importedDate = modificationDate(imported) ?? .distantPast
            return importedDate > bundledDate ? .imported(imported) : .bundled(bundled)
        case (let bundled?, nil):
            return .bundled(bundled)
        case (nil, let imported?):
            return .imported(imported)
        default:
            return nil
        }
    }

    /// Model file extensions the app opens. GGUF is what every quantiser
    /// emits, so it is the common case rather than the exception.
    static let supportedExtensions = ["gguf", "mdlo"]

    /// Types the document picker will enable. The declared types come first,
    /// but a file copied onto the device before the app was installed can
    /// still carry a generic type, so the broader ones stay in the list —
    /// otherwise the model shows up greyed out and unselectable.
    static var pickableTypes: [UTType] {
        var types: [UTType] = []
        for identifier in ["com.mira.voice.mdlo", "org.ggml.gguf"] {
            if let declared = UTType(identifier) { types.append(declared) }
        }
        for suffix in supportedExtensions {
            if let byExtension = UTType(filenameExtension: suffix),
               !types.contains(byExtension) { types.append(byExtension) }
        }
        types.append(.data)
        types.append(.item)
        return types
    }

    /// The bundled Kokoro voice, if this build shipped one. CI copies the
    /// unpacked model in as a folder reference, so it keeps its structure —
    /// espeak-ng-data in particular is a directory the engine reads by path.
    static func bundledKokoroDirectory() -> URL? {
        guard let url = Bundle.main.url(forResource: "kokoro", withExtension: nil),
              FileManager.default.fileExists(atPath:
                url.appendingPathComponent("model.int8.onnx").path) else { return nil }
        return url
    }

    /// The bundled streaming speech model, if this build shipped one.
    static func bundledSpeechDirectory() -> URL? {
        guard let url = Bundle.main.url(forResource: "speech", withExtension: nil),
              FileManager.default.fileExists(atPath:
                url.appendingPathComponent("encoder.onnx").path) else { return nil }
        return url
    }

    static func bundledModel() -> URL? {
        for suffix in supportedExtensions {
            if let url = Bundle.main.url(forResource: "mira", withExtension: suffix) {
                return url
            }
        }
        return nil
    }

    /// The newest model sitting in Documents, whatever it is called. Scanning
    /// rather than looking for one fixed name means a file dropped in through
    /// Files ▸ On My iPhone ▸ Mira is found without being renamed first.
    static func importedModel() -> URL? {
        importedModels().first
    }

    static func importedModels() -> [URL] {
        guard let directory = documentsDirectory(),
              let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return [] }
        return entries
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { (modificationDate($0) ?? .distantPast) > (modificationDate($1) ?? .distantPast) }
    }

    static func documentsDirectory() -> URL? {
        try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
    }

    /// Copies an imported file into Documents and returns its location.
    @discardableResult
    static func install(from source: URL) throws -> URL {
        guard let directory = documentsDirectory() else {
            throw CocoaError(.fileNoSuchFile)
        }
        // Keep the file's own name: it is how the user tells one quantisation
        // from another, and it is what the model summary is derived from.
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        // Files ▸ On My iPhone ▸ Mira writes straight into Documents, so the
        // picked file can already *be* the destination. Copying would delete
        // it first and then have nothing left to copy.
        if source.standardizedFileURL == destination.standardizedFileURL {
            return destination
        }

        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = destination
        try? mutable.setResourceValues(values)

        return destination
    }

    /// Removes every imported model, falling back to the bundled one.
    static func removeImported() {
        for url in importedModels() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Frees the extracted GGUF cache. The model still works afterwards — it
    /// just re-extracts on next launch.
    static func clearExtractedCache() {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil, create: false)
            .appendingPathComponent("MiraModels", isDirectory: true) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    static func diskUsageDescription() -> String {
        var total = 0
        for url in importedModels() { total += fileSize(url) }
        if let dir = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil, create: false)
            .appendingPathComponent("MiraModels", isDirectory: true),
           let files = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                    includingPropertiesForKeys: [.fileSizeKey]) {
            total += files.reduce(0) { $0 + fileSize($1) }
        }
        return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
    }

    private static func fileSize(_ url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? Int ?? 0
    }

    private static func modificationDate(_ url: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }
}
