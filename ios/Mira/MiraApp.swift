import SwiftUI
import UniformTypeIdentifiers

@main
struct MiraApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    @StateObject private var call = CallViewModel()
    @State private var showImporter = false
    @State private var model: ModelLocator.Source?
    @State private var permissionDenied = false

    /// Held here, not because this view draws with it, but because Palette
    /// reads the theme at draw time — observing it is what makes a colour
    /// change re-render everything below.
    @AppStorage(Prefs.themeKey) private var theme = Theme.butter.rawValue
    @AppStorage(Prefs.onboardedKey) private var onboarded = false

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                if model == nil {
                    ImportPrompt(showImporter: $showImporter)
                } else if !onboarded {
                    OnboardingView(call: call) { onboarded = true }
                } else {
                    TalkView(call: call, listener: call.listener,
                             permissionDenied: $permissionDenied)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Palette.skyDeep)
        .preferredColorScheme(.light)
        .task {
            if model == nil { model = ModelLocator.current() }
            if let model, call.transcript.isEmpty {
                call.load(modelURL: model.url)
            }
            permissionDenied = !(await call.listener.requestPermissions())
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: ModelLocator.pickableTypes,
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let picked = urls.first else { return }
            importModel(from: picked)
        }
        .onOpenURL { url in importModel(from: url) }
    }

    private func importModel(from url: URL) {
        do {
            let installed = try ModelLocator.install(from: url)
            model = .imported(installed)
            call.load(modelURL: installed)
        } catch {
            call.reportFailure("Couldn't import that file: \(error.localizedDescription)")
        }
    }
}

// MARK: - Talk

private struct TalkView: View {
    @ObservedObject var call: CallViewModel
    /// Observed directly: `audioLevel` and `partialText` live on the listener,
    /// and a nested ObservableObject never redraws its owner's views.
    @ObservedObject var listener: SpeechListener
    @Binding var permissionDenied: Bool

    /// The full transcript is a mode rather than the main screen: what is
    /// being said now is captioned under Mira, and the scrollback is one tap
    /// away. Remembered, because whichever way you read is the way you keep
    /// reading.
    @AppStorage(Prefs.expandedKey) private var expanded = false
    @AppStorage(Prefs.nameKey) private var yourName = ""

    private var hasConversation: Bool {
        call.transcript.contains { $0.role != .system } || !call.liveMiraText.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            MiraHeader(call: call, showingTranscript: $expanded)

            if expanded {
                LiveTranscript(call: call, listener: listener)
            } else {
                if resting { greeting }
                Spacer(minLength: 0)
                MiraFace(phase: call.phase, level: listener.audioLevel)
                CaptionBand(caption: caption)
                Spacer(minLength: 0)
            }

            statusLine
            controlRow
        }
        .animation(.easeInOut(duration: 0.25), value: expanded)
    }

    /// Nothing has happened yet — no conversation, nothing being said, nothing
    /// wrong. The only moment the greeting is worth the line it takes.
    private var resting: Bool {
        !hasConversation && caption == nil && call.phase == .idle && !permissionDenied
    }

    /// Closed captions for whoever is talking: Mira's own words as she says
    /// them, or yours as they are transcribed.
    private var caption: Caption? {
        if call.phase == .listening {
            let heard = listener.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
            return heard.isEmpty ? nil : Caption.said(heard, isMira: false)
        }
        return call.caption
    }

    /// Everything reachable without shifting your grip: the three things you
    /// press during a call sit in the bottom third, mic in the middle.
    private var controlRow: some View {
        HStack(alignment: .center, spacing: 0) {
            NavigationLink {
                SessionsView(store: call.sessions, call: call)
            } label: {
                sideControl("clock.arrow.circlepath", label: "Previous sessions")
            }
            .frame(maxWidth: .infinity)

            TalkButton(call: call, disabled: permissionDenied)

            Menu {
                Button("Replay Mira's last reply", systemImage: "gobackward") {
                    call.replayLastReply()
                }
                .disabled(!call.canReplay)
                Button("Ask that again", systemImage: "arrow.clockwise") {
                    call.retryLastTurn()
                }
                .disabled(!call.canRetry)
                Divider()
                Button("New conversation", systemImage: "square.and.pencil") { call.reset() }
            } label: {
                sideControl("ellipsis", label: "More")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
    }

    private func sideControl(_ system: String, label: String) -> some View {
        Image(systemName: system)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Palette.skyInk)
            .frame(width: 48, height: 48)
            .background(Circle().fill(Palette.card).shadow(color: Palette.shadowSoft, radius: 7, y: 3))
            .accessibilityLabel(label)
    }

    /// One line, or nothing. What is being said is captioned, and what she is
    /// doing is visible in how she moves, so this is left with only what
    /// neither of those can show: something loading, or something wrong.
    @ViewBuilder
    private var statusLine: some View {
        if let text = status {
            Text(text)
                .font(.system(size: 14.5, weight: .medium, design: .rounded))
                .foregroundStyle(isFailure ? Palette.alert : Palette.inkSoft)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
                .padding(.top, 10)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: text)
        }
    }

    private var isFailure: Bool {
        if case .failed = call.phase { return true }
        return permissionDenied
    }

    private var status: String? {
        if permissionDenied { return "Microphone is off — turn it on in Settings" }
        switch call.phase {
        case .loading(let message):            return message
        case .failed(let message):             return message
        case .listening, .thinking, .speaking: return nil
        case .idle:                            return call.voiceNotice
        }
    }

    private var greeting: some View {
        Text(yourName.isEmpty ? Self.timeGreeting : "\(Self.timeGreeting), \(yourName)")
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(Palette.inkSoft)
            .padding(.top, 10)
    }

    private static var timeGreeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        case 18..<22: return "Good evening"
        default:      return "Still up?"
        }
    }

}

/// Closed captions under Mira.
///
/// The word being said is picked out, the words before it stand in full ink,
/// and the ones still coming are faint — so a glance tells you both what was
/// said and where in the sentence she is. One `Text` built from an
/// `AttributedString` rather than a row of word views, so it wraps and hyphenates
/// the way any other paragraph does.
private struct CaptionBand: View {
    let caption: Caption?

    /// Three lines' worth, held whether or not there is anything to say, so
    /// Mira doesn't jump up and down the screen as she starts and stops.
    private static let bandHeight: CGFloat = 92
    private static let size: CGFloat = 24

    var body: some View {
        Text(styled)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, minHeight: Self.bandHeight)
            .padding(.horizontal, 26)
            .animation(.easeOut(duration: 0.14), value: caption)
    }

    private var styled: AttributedString {
        guard let caption, !caption.isEmpty else { return AttributedString() }
        var line = AttributedString()
        for (index, word) in caption.words.enumerated() {
            var piece = AttributedString(word)
            piece.foregroundColor = colour(at: index, in: caption)
            piece.font = .system(size: Self.size,
                                 weight: index == caption.index ? .heavy : .semibold,
                                 design: .rounded)
            line += piece
            if index < caption.words.count - 1 { line += AttributedString(" ") }
        }
        return line
    }

    /// Your own words are all in the accent, since they have all been said by
    /// the time they are transcribed; Mira's are staged.
    private func colour(at index: Int, in caption: Caption) -> Color {
        guard caption.isMira else { return Palette.skyInk }
        if index == caption.index { return Palette.skyDeep }
        return index < caption.index ? Palette.ink : Palette.inkFaint
    }
}

private struct MiraHeader: View {
    @ObservedObject var call: CallViewModel
    @Binding var showingTranscript: Bool
    @State private var showSettings = false

    var body: some View {
        HStack {
            RoundedIconButton(system: showingTranscript ? "person.wave.2.fill" : "text.alignleft",
                              tint: Palette.skyInk) {
                showingTranscript.toggle()
            }
            .accessibilityLabel(showingTranscript ? "Back to Mira" : "Show transcript")
            Spacer()
            Text("Mira")
                .font(.system(size: 27, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.ink)
            Spacer()
            RoundedIconButton(system: "gearshape.fill", tint: Palette.inkSoft) {
                showSettings = true
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .sheet(isPresented: $showSettings) { SettingsView(call: call) }
    }
}

struct RoundedIconButton: View {
    let system: String
    var tint: Color = Palette.skyDeep
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(
                    Circle().fill(Palette.card)
                        .shadow(color: Palette.shadowSoft, radius: 8, y: 3)
                )
        }
    }
}

private struct TalkButton: View {
    @ObservedObject var call: CallViewModel
    let disabled: Bool

    var body: some View {
        Button {
            switch call.phase {
            case .listening: call.listener.finishTurn()
            case .speaking, .thinking: call.interrupt()
            default: call.beginListening()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Palette.sky.opacity(0.35))
                    .frame(width: 94, height: 94)
                Circle()
                    .fill(LinearGradient(colors: [Palette.sky, Palette.skyDeep],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 74, height: 74)
                    .shadow(color: Palette.skyDeep.opacity(0.35), radius: 14, y: 6)
                Image(systemName: glyph)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    private var glyph: String {
        switch call.phase {
        case .listening: return "stop.fill"
        case .speaking, .thinking: return "hand.raised.fill"
        default: return "mic.fill"
        }
    }

    private var label: String {
        switch call.phase {
        case .listening: return "Stop talking"
        case .speaking:  return "Interrupt Mira"
        case .thinking:  return "Cancel"
        default:         return "Talk to Mira"
        }
    }
}

private struct LiveTranscript: View {
    @ObservedObject var call: CallViewModel
    @ObservedObject var listener: SpeechListener

    /// Whether the newest line is on screen. Auto-scrolling regardless is what
    /// makes a transcript fight you: read back three turns and it yanks you
    /// to the bottom the moment Mira says another word.
    @State private var atBottom = true

    private var spoken: [ChatMessage] { call.transcript.filter { $0.role != .system } }

    var body: some View {
        if spoken.isEmpty && call.liveMiraText.isEmpty {
            VStack {
                Spacer()
                Text("Nothing said yet.")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Palette.inkFaint)
                Spacer()
            }
        } else {
            scrollback
        }
    }

    private var scrollback: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(spoken) { message in
                        ChatBubble(text: message.text, isMira: message.role == .assistant)
                            .id(message.id)
                    }
                    // Mira's reply, growing sentence by sentence as it is
                    // generated rather than appearing all at once at the end.
                    if !call.liveMiraText.isEmpty {
                        ChatBubble(text: call.liveMiraText, isMira: true)
                            .id("live")
                    }
                    if call.phase == .listening, !listener.partialText.isEmpty {
                        ChatBubble(text: listener.partialText, isMira: false)
                            .opacity(0.55).id("partial")
                    }
                    // A tail marker rather than a scroll offset: whether this
                    // is on screen is exactly the question being asked, and it
                    // works back to iOS 17.
                    Color.clear
                        .frame(height: 1)
                        .id("tail")
                        .onAppear { atBottom = true }
                        .onDisappear { atBottom = false }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .overlay(alignment: .bottom) {
                if !atBottom {
                    Button {
                        withAnimation { proxy.scrollTo("tail", anchor: .bottom) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 11, weight: .bold))
                            Text("Latest")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(
                            Capsule().fill(Palette.skyDeep)
                                .shadow(color: Palette.shadow, radius: 8, y: 3)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: atBottom)
            .onChange(of: call.transcript.count) { _, _ in
                guard atBottom else { return }
                withAnimation { proxy.scrollTo("tail", anchor: .bottom) }
            }
            .onChange(of: call.liveMiraText) { _, _ in
                guard atBottom else { return }
                withAnimation { proxy.scrollTo("tail", anchor: .bottom) }
            }
            .onChange(of: listener.partialText) { _, _ in
                guard atBottom else { return }
                withAnimation { proxy.scrollTo("tail", anchor: .bottom) }
            }
        }
    }
}

// MARK: - Onboarding

private struct ImportPrompt: View {
    @Binding var showImporter: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            MiraFace(phase: .idle, level: 0, height: 250)
            Text("Mira")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.ink)
            Text("Pick a .gguf or .mdlo model to get started.\nShe runs entirely on this phone.")
                .multilineTextAlignment(.center)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Palette.inkSoft)
                .padding(.horizontal, 40)
            Button { showImporter = true } label: {
                Text("Choose model file")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .padding(.horizontal, 30).padding(.vertical, 15)
                    .background(
                        Capsule().fill(LinearGradient(colors: [Palette.sky, Palette.skyDeep],
                                                      startPoint: .leading, endPoint: .trailing))
                            .shadow(color: Palette.skyDeep.opacity(0.3), radius: 12, y: 5)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Or drop the model into Files ▸ On My iPhone ▸ Mira\nand reopen the app.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.inkFaint)
                .padding(.bottom, 26)
        }
    }
}
