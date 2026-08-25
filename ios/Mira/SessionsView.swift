import SwiftUI

/// Previous Sessions: search, date filters, a usage card, and every saved
/// conversation newest first.
struct SessionsView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var filter: SessionFilter = .all
    @State private var confirmingDeleteAll = false

    private var results: [ChatSession] {
        store.filtered(matching: query, filter: filter)
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    searchField
                    filters
                    usageCard
                    if results.isEmpty {
                        emptyState
                    } else {
                        conversations
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Delete every saved chat?",
                            isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
            Button("Delete all chats", role: .destructive) { store.deleteAll() }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text("This can't be undone. Nothing was ever uploaded, so there is no copy elsewhere.")
        }
    }

    private var header: some View {
        HStack {
            RoundedIconButton(system: "arrow.left", tint: Palette.ink) { dismiss() }
                .accessibilityLabel("Back")
            Spacer()
            Text("Previous Sessions")
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.ink)
            Spacer()
            RoundedIconButton(system: "trash.fill", tint: Palette.alert) {
                confirmingDeleteAll = true
            }
            .accessibilityLabel("Delete all chats")
            .opacity(store.sessions.isEmpty ? 0.35 : 1)
            .disabled(store.sessions.isEmpty)
        }
        .padding(.top, 8)
    }

    private var searchField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
            TextField("Search past voice notes and topics…", text: $query)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Palette.ink)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.inkFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 15)
        .background(
            Capsule().fill(Palette.card).shadow(color: Palette.shadowSoft, radius: 8, y: 3)
        )
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(SessionFilter.allCases) { option in
                    let active = option == filter
                    Button { filter = option } label: {
                        Text(option == .all ? "All (\(store.sessions.count))" : option.label)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(active ? .white : Palette.inkSoft)
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(active ? AnyShapeStyle(LinearGradient(
                                            colors: [Palette.sky, Palette.skyDeep],
                                            startPoint: .leading, endPoint: .trailing))
                                        : AnyShapeStyle(Palette.card))
                                    .shadow(color: Palette.shadowSoft, radius: 6, y: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var usageCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("SESSION USAGE")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded)).kerning(1)
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                Text("100% LOCAL")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).kerning(0.6)
                    .foregroundStyle(Palette.skyInk)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Palette.powder.opacity(0.8)))
            }
            HStack(spacing: 10) {
                stat("\(store.totalMinutes)", "MINUTES", Palette.powder.opacity(0.55))
                stat("\(store.sessions.count)", "CHATS", Palette.peach.opacity(0.8))
                stat(store.cloudBytes, "CLOUD SYNC", Palette.butterDeep.opacity(0.9))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Palette.card)
                .shadow(color: Palette.shadow, radius: 12, y: 5)
        )
    }

    private func stat(_ value: String, _ caption: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 25, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: 10, weight: .bold, design: .rounded)).kerning(0.5)
                .foregroundStyle(Palette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint))
    }

    private var conversations: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(query.isEmpty ? "Recent Conversations" : "\(results.count) found")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            ForEach(results) { session in
                NavigationLink {
                    SessionTranscript(session: session)
                } label: {
                    SessionCard(session: session)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        store.delete(session)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: query.isEmpty ? "bubble.left.and.bubble.right.fill" : "magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Palette.sky)
            Text(query.isEmpty ? "No chats yet" : "Nothing matches “\(query)”")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            if query.isEmpty {
                Text("Talk to Mira and your conversations\nwill collect here.")
                    .font(.system(size: 14, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

private struct SessionCard: View {
    let session: ChatSession

    /// Rotates through the pastels so a list of chats reads as a list rather
    /// than a wall of identical cards.
    private var accent: Color {
        let palette = [Palette.powder, Palette.peach, Palette.butterDeep]
        return palette[abs(session.id.hashValue) % palette.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 13) {
                ZStack {
                    Circle().fill(accent).frame(width: 46, height: 46)
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.skyInk)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .font(.system(size: 16.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(dateLabel)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded)).kerning(0.5)
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 6)
                Text(session.durationLabel)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.inkSoft)
                    .monospacedDigit()
            }

            if !session.preview.isEmpty {
                Text("“\(session.preview)”")
                    .font(.system(size: 14.5, design: .rounded))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(Palette.powder)

            HStack {
                Text("\(session.messages.count) MESSAGES")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded)).kerning(0.6)
                    .foregroundStyle(Palette.inkFaint)
                Spacer()
                HStack(spacing: 5) {
                    Text("View transcript")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Palette.skyDeep)
            }
        }
        .padding(17)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.card)
                .shadow(color: Palette.shadow, radius: 12, y: 5)
        )
    }

    private var dateLabel: String {
        let calendar = Calendar.current
        let time = session.startedAt.formatted(date: .omitted, time: .shortened).uppercased()
        if calendar.isDateInToday(session.startedAt) { return "TODAY · \(time)" }
        if calendar.isDateInYesterday(session.startedAt) { return "YESTERDAY · \(time)" }
        let day = session.startedAt.formatted(.dateTime.month(.abbreviated).day()).uppercased()
        return "\(day) · \(time)"
    }
}

private struct SessionTranscript: View {
    let session: ChatSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    RoundedIconButton(system: "arrow.left", tint: Palette.ink) { dismiss() }
                        .accessibilityLabel("Back")
                    Spacer()
                    VStack(spacing: 1) {
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.ink)
                        Text(session.durationLabel)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    Spacer()
                    Color.clear.frame(width: 46, height: 46)
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 6)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(session.messages.enumerated()), id: \.offset) { _, turn in
                            ChatBubble(text: turn.text, isMira: turn.isMira)
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 12)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// One line of conversation, shared by the live transcript and saved chats so
/// a saved chat never looks unlike the call it came from.
struct ChatBubble: View {
    let text: String
    let isMira: Bool

    var body: some View {
        HStack {
            if !isMira { Spacer(minLength: 44) }
            Text(text)
                .font(.system(size: 15.5, design: .rounded))
                .foregroundStyle(isMira ? Palette.ink : .white)
                .padding(.horizontal, 15).padding(.vertical, 11)
                .background(background)
            if isMira { Spacer(minLength: 44) }
        }
    }

    @ViewBuilder
    private var background: some View {
        if isMira {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(Palette.card)
                .shadow(color: Palette.shadowSoft, radius: 7, y: 3)
        } else {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(LinearGradient(colors: [Palette.sky, Palette.skyDeep],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: Palette.skyDeep.opacity(0.25), radius: 7, y: 3)
        }
    }
}
