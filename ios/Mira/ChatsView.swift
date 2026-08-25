import SwiftUI

/// The Chats tab: every conversation Mira has had, newest first.
struct ChatsView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                if store.sessions.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Chats")
            .toolbarBackground(Palette.cream, for: .navigationBar)
            .toolbar {
                if !store.sessions.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Delete all chats", role: .destructive) { store.deleteAll() }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .tint(Palette.hotPink)
                    }
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(store.sessions) { session in
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
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Palette.sherbet)
            Text("No chats yet")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink)
            Text("Talk to Mira and your conversations\nwill collect here.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.inkSoft)
        }
        .padding(40)
    }
}

private struct SessionCard: View {
    let session: ChatSession

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 10)
                Text(session.startedAt, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(Palette.inkFaint)
            }
            if !session.preview.isEmpty {
                Text(session.preview)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            HStack(spacing: 6) {
                Circle().fill(Palette.hotPink).frame(width: 5, height: 5)
                Text("\(session.messages.count) messages")
                    .font(.caption2)
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.card)
                .shadow(color: Palette.shadow, radius: 10, y: 4)
        )
    }
}

/// A saved conversation, read-only.
private struct SessionTranscript: View {
    let session: ChatSession

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(session.messages.enumerated()), id: \.offset) { _, turn in
                        ChatBubble(text: turn.text, isMira: turn.isMira)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
        }
        .navigationTitle(session.startedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.cream, for: .navigationBar)
    }
}

/// One line of conversation. Shared by the live transcript and saved chats so
/// a chat never looks different from the call it came from.
struct ChatBubble: View {
    let text: String
    let isMira: Bool

    var body: some View {
        HStack {
            if !isMira { Spacer(minLength: 44) }
            Text(text)
                .font(.system(size: 15.5))
                .foregroundStyle(isMira ? Palette.ink : .white)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(bubbleBackground)
            if isMira { Spacer(minLength: 44) }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isMira {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(Palette.card)
                .shadow(color: Palette.shadow, radius: 8, y: 3)
        } else {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(LinearGradient(colors: [Palette.hotPink, Palette.deepRose],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: Palette.hotPink.opacity(0.3), radius: 8, y: 3)
        }
    }
}
