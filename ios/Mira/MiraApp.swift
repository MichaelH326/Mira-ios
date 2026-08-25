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
    @State private var showSettings = false
    @State private var permissionDenied = false
    @State private var model: ModelLocator.Source?

    var body: some View {
        Group {
            if model == nil {
                ZStack {
                    Palette.background.ignoresSafeArea()
                    ImportPrompt(showImporter: $showImporter)
                }
            } else {
                TabView {
                    TalkView(call: call,
                             permissionDenied: $permissionDenied,
                             showSettings: $showSettings)
                        .tabItem { Label("Talk", systemImage: "waveform") }

                    ChatsView(store: call.sessions)
                        .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right.fill") }
                }
                .tint(Palette.hotPink)
            }
        }
        .preferredColorScheme(.light)
        .task {
            // A bundled model loads immediately — no setup step on first launch.
            if model == nil { model = ModelLocator.current() }
            if let model, call.transcript.isEmpty {
                call.load(modelURL: model.url)
            }
            permissionDenied = !(await SpeechListener.requestPermissions())
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: ModelLocator.pickableTypes,
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let picked = urls.first else { return }
            importModel(from: picked)
        }
        // A .mdlo shared to Mira from Files or another app.
        .onOpenURL { url in importModel(from: url) }
        .sheet(isPresented: $showSettings) {
            SettingsView(call: call, model: $model, showImporter: $showImporter)
        }
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
    @Binding var permissionDenied: Bool
    @Binding var showSettings: Bool

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                orbArea
                statusLine
                LiveTranscript(call: call)
            }
        }
    }

    private var header: some View {
        HStack {
            Button { call.reset() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.hotPink)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Palette.card.opacity(0.85)))
            }
            .accessibilityLabel("Start a new conversation")

            Spacer()

            VStack(spacing: 2) {
                Text("Mira")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                Text(call.modelDescription.isEmpty ? "on this phone" : call.modelDescription)
                    .font(.caption2)
                    .foregroundStyle(Palette.inkFaint)
            }

            Spacer()

            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.hotPink)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Palette.card.opacity(0.85)))
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    /// Tapping the orb is the whole interaction: start a turn, end a turn,
    /// or cut Mira off while she's talking.
    private var orbArea: some View {
        Button {
            switch call.phase {
            case .listening: call.listener.finishTurn()
            case .speaking, .thinking: call.interrupt()
            default: call.beginListening()
            }
        } label: {
            VoiceOrb(phase: call.phase, level: call.listener.audioLevel)
        }
        .buttonStyle(.plain)
        .disabled(permissionDenied)
        .accessibilityLabel(orbLabel)
        .padding(.vertical, 4)
    }

    private var orbLabel: String {
        switch call.phase {
        case .listening: return "Stop talking"
        case .speaking:  return "Interrupt Mira"
        case .thinking:  return "Cancel"
        default:         return "Talk to Mira"
        }
    }

    private var statusLine: some View {
        Group {
            switch call.phase {
            case .loading(let message):
                pill(message, icon: "hourglass", tint: Palette.lilac)
            case .listening:
                pill(call.listener.partialText.isEmpty ? "Listening…" : call.listener.partialText,
                     icon: "waveform", tint: Palette.hotPink)
            case .thinking:
                pill("Thinking…", icon: "sparkles", tint: Palette.lilac)
            case .speaking:
                pill("Tap to jump in", icon: "speaker.wave.2.fill", tint: Palette.sherbet)
            case .failed(let message):
                pill(message, icon: "exclamationmark.triangle.fill", tint: Palette.alert)
            case .idle:
                pill(permissionDenied ? "Microphone is off — turn it on in Settings" : "Tap to talk",
                     icon: permissionDenied ? "mic.slash.fill" : "hand.tap.fill",
                     tint: Palette.inkFaint)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
        .animation(.easeInOut(duration: 0.22), value: call.phase)
    }

    private func pill(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint == Palette.sherbet ? Palette.deepRose : tint)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
            Capsule().fill(Palette.card.opacity(0.9))
                .shadow(color: Palette.shadow, radius: 8, y: 3)
        )
    }
}

// MARK: - Live transcript

private struct LiveTranscript: View {
    @ObservedObject var call: CallViewModel

    private var spoken: [ChatMessage] { call.transcript.filter { $0.role != .system } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if spoken.isEmpty && call.liveMiraText.isEmpty {
                        opener
                    }
                    ForEach(spoken) { message in
                        ChatBubble(text: message.text, isMira: message.role == .assistant)
                            .id(message.id)
                    }
                    if !call.liveMiraText.isEmpty {
                        ChatBubble(text: call.liveMiraText, isMira: true).id("live")
                    }
                    if call.phase == .listening, !call.listener.partialText.isEmpty {
                        ChatBubble(text: call.listener.partialText, isMira: false)
                            .opacity(0.5).id("partial")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
            .onChange(of: call.transcript.count) { _, _ in
                withAnimation { proxy.scrollTo(call.transcript.last?.id, anchor: .bottom) }
            }
            .onChange(of: call.liveMiraText) { _, _ in
                withAnimation { proxy.scrollTo("live", anchor: .bottom) }
            }
        }
    }

    /// The transcript is empty on every launch; say something rather than
    /// leaving half the screen blank.
    private var opener: some View {
        VStack(spacing: 6) {
            Text("Say hello")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.inkSoft)
            Text("Everything stays on this phone.")
                .font(.caption)
                .foregroundStyle(Palette.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26)
    }
}

// MARK: - Settings

private struct SettingsView: View {
    @ObservedObject var call: CallViewModel
    @Binding var model: ModelLocator.Source?
    @Binding var showImporter: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                Form {
                    Section("Model") {
                        row("Source", (model?.isBundled ?? false) ? "Built in" : "Imported")
                        row("Details", call.modelDescription)
                        row("Voice", call.speaker.describedVoice)
                        row("Storage used", ModelLocator.diskUsageDescription())
                    }
                    .listRowBackground(Palette.card)

                    Section {
                        Button("Replace with a different model…") { showImporter = true; dismiss() }
                            .foregroundStyle(Palette.hotPink)
                        if model?.isBundled == false {
                            Button("Remove imported model", role: .destructive) {
                                ModelLocator.removeImported()
                                model = ModelLocator.current()
                                if let model { call.load(modelURL: model.url) }
                                dismiss()
                            }
                        }
                        Button("Free extracted cache") {
                            ModelLocator.clearExtractedCache()
                            dismiss()
                        }
                        .foregroundStyle(Palette.hotPink)
                    } footer: {
                        Text("Mira runs entirely on this phone. Nothing you say leaves it.")
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .listRowBackground(Palette.card)

                    Section("Conversation") {
                        Toggle("Keep listening after Mira replies", isOn: $call.handsFree)
                            .tint(Palette.hotPink)
                    }
                    .listRowBackground(Palette.card)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .toolbarBackground(Palette.cream, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.hotPink)
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.ink)
            Spacer()
            Text(value).foregroundStyle(Palette.inkSoft)
        }
    }
}

// MARK: - Onboarding

private struct ImportPrompt: View {
    @Binding var showImporter: Bool

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Palette.sherbet, Palette.hotPink],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 120)
                    .shadow(color: Palette.hotPink.opacity(0.3), radius: 22, y: 8)
                Image(systemName: "mic.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.white)
            }
            Text("Mira")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)
            Text("Pick a model to get started.\nShe runs entirely on this phone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.inkSoft)
                .padding(.horizontal, 40)
            Button {
                showImporter = true
            } label: {
                Text("Choose model file")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 30).padding(.vertical, 15)
                    .background(
                        Capsule().fill(LinearGradient(colors: [Palette.hotPink, Palette.deepRose],
                                                      startPoint: .leading, endPoint: .trailing))
                            .shadow(color: Palette.hotPink.opacity(0.35), radius: 12, y: 5)
                    )
                    .foregroundStyle(.white)
            }
            Spacer()
            Text("Or put mira.mdlo in Files ▸ On My iPhone ▸ Mira\nand reopen the app.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.inkFaint)
                .padding(.bottom, 30)
        }
    }
}
