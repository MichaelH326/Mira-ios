import Foundation

/// One saved conversation.
struct ChatSession: Identifiable, Codable, Equatable {

    struct Turn: Codable, Equatable {
        var isMira: Bool
        var text: String
    }

    let id: UUID
    var startedAt: Date
    var messages: [Turn]

    /// What the Chats list shows. The first thing the user said is a better
    /// handle on a conversation than the date is.
    var title: String {
        let opener = messages.first(where: { !$0.isMira })?.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let opener, !opener.isEmpty else { return "New conversation" }
        return opener.count > 60 ? String(opener.prefix(60)) + "…" : opener
    }

    var preview: String {
        messages.last?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// Saved conversations, kept as one JSON file in Application Support.
///
/// Everything Mira hears stays on the phone, so the transcript does too — the
/// file is excluded from iCloud backup for the same reason the models are.
@MainActor
final class SessionStore: ObservableObject {

    @Published private(set) var sessions: [ChatSession] = []

    /// Oldest conversations fall off rather than growing without bound.
    private let limit = 200
    private let fileURL: URL?

    init() {
        fileURL = Self.storeURL()
        load()
    }

    /// Inserts or updates a conversation, newest first.
    func record(_ session: ChatSession) {
        guard !session.messages.isEmpty else { return }
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        if sessions.count > limit { sessions.removeLast(sessions.count - limit) }
        save()
    }

    func delete(_ session: ChatSession) {
        sessions.removeAll { $0.id == session.id }
        save()
    }

    func deleteAll() {
        sessions.removeAll()
        save()
    }

    private static func storeURL() -> URL? {
        guard let directory = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                           in: .userDomainMask,
                                                           appropriateFor: nil, create: true)
        else { return nil }
        let folder = directory.appendingPathComponent("MiraSessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("sessions.json")
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        sessions = (try? decoder.decode([ChatSession].self, from: data)) ?? []
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = fileURL
        try? mutable.setResourceValues(values)
    }
}
