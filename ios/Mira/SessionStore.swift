import Foundation

enum SessionFilter: String, CaseIterable, Identifiable {
    case all, today, thisWeek
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:      return "All"
        case .today:    return "Today"
        case .thisWeek: return "This Week"
        }
    }
}

/// One saved conversation.
struct ChatSession: Identifiable, Codable, Equatable {

    struct Turn: Codable, Equatable {
        var isMira: Bool
        var text: String
    }

    let id: UUID
    var startedAt: Date
    /// Optional so a file written before durations existed still decodes —
    /// a missing key on a non-optional would throw away every saved chat.
    var endedAt: Date?
    var messages: [Turn]

    var duration: TimeInterval {
        max(0, (endedAt ?? startedAt).timeIntervalSince(startedAt))
    }

    /// "4m 12s", or "48s" for a short one.
    var durationLabel: String {
        let total = Int(duration.rounded())
        let minutes = total / 60, seconds = total % 60
        return minutes > 0 ? "\(minutes)m \(String(format: "%02d", seconds))s" : "\(seconds)s"
    }

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

    // MARK: - Totals, for the usage card

    var totalMessages: Int {
        sessions.reduce(0) { $0 + $1.messages.count }
    }

    var totalMinutes: Int {
        Int((sessions.reduce(0) { $0 + $1.duration } / 60).rounded())
    }

    /// Nothing is ever uploaded, so this is always zero — which is the point
    /// of showing it.
    var cloudBytes: String { "0 B" }

    func filtered(matching query: String, filter: SessionFilter) -> [ChatSession] {
        let calendar = Calendar.current
        return sessions.filter { session in
            let inRange: Bool
            switch filter {
            case .all:      inRange = true
            case .today:    inRange = calendar.isDateInToday(session.startedAt)
            case .thisWeek: inRange = calendar.isDate(session.startedAt,
                                                      equalTo: Date(), toGranularity: .weekOfYear)
            }
            guard inRange else { return false }
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return true }
            return session.messages.contains { $0.text.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    /// Writes the saved chats somewhere the share sheet can reach, as plain
    /// readable text rather than the internal JSON.
    func exportFile() -> URL? {
        guard !sessions.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var out = "Mira — saved conversations\n"
        out += "Exported \(formatter.string(from: Date()))\n"
        for session in sessions {
            out += "\n\n———\n\(formatter.string(from: session.startedAt))"
            out += "  ·  \(session.durationLabel)  ·  \(session.messages.count) messages\n\n"
            for turn in session.messages {
                out += "\(turn.isMira ? "Mira" : "You"): \(turn.text)\n"
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mira-chats.txt")
        do {
            try out.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
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
