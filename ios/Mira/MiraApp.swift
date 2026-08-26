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

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                if model == nil {
                    ImportPrompt(showImporter: $showImporter)
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

    private var hasConversation: Bool {
        call.transcript.contains { $0.role != .system } || !call.liveMiraText.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            MiraHeader(call: call)
            privacyBadge
            greeting

            MiraFace(phase: call.phase, level: listener.audioLevel)
                .padding(.top, 2)

            WaveBars(level: listener.audioLevel, phase: call.phase)
                .padding(.bottom, 8)

            StatusCard(call: call, listener: listener, permissionDenied: permissionDenied)
                .padding(.horizontal, 20)

            if let notice = call.voiceNotice {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash").font(.system(size: 10, weight: .bold))
                    Text(notice)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .lineLimit(2)
                }
                .foregroundStyle(Palette.inkSoft)
                .padding(.horizontal, 24)
                .padding(.top, 7)
            }

            if hasConversation {
                LiveTranscript(call: call, listener: listener).padding(.top, 10)
            } else {
                Starters(call: call).padding(.top, 14)
                Spacer(minLength: 8)
            }

            sessionsLink
            TalkButton(call: call, disabled: permissionDenied)
                .padding(.bottom, 18)
        }
    }

    /// Only claims privacy when it is true: with the Edge voice selected, the
    /// text of Mira's replies is sent to Microsoft to be spoken.
    private var privacyBadge: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(call.isFullyLocal ? Palette.skyDeep : Palette.amber)
                .frame(width: 6, height: 6)
            Text(call.isFullyLocal ? "ON-DEVICE & PRIVATE" : "VOICE VIA MICROSOFT")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(0.8)
                .foregroundStyle(call.isFullyLocal ? Palette.skyInk : Palette.ink)
        }
        .padding(.horizontal, 15).padding(.vertical, 8)
        .background(Capsule().fill(Palette.powder.opacity(0.75)))
        .padding(.top, 4)
    }

    private var greeting: some View {
        Text(Self.timeGreeting)
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

    private var sessionsLink: some View {
        NavigationLink {
            SessionsView(store: call.sessions)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 13, weight: .bold))
                Text("PREVIOUS SESSIONS")
                    .font(.system(size: 12, weight: .bold, design: .rounded)).kerning(0.9)
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(Palette.skyInk)
            .padding(.vertical, 12)
        }
    }
}

private struct MiraHeader: View {
    @ObservedObject var call: CallViewModel
    @State private var showSettings = false

    var body: some View {
        HStack {
            RoundedIconButton(system: "sparkles", tint: Palette.amber) {}
                .allowsHitTesting(false)
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

/// The white card under the face: what Mira is doing, and the last thing said.
private struct StatusCard: View {
    @ObservedObject var call: CallViewModel
    @ObservedObject var listener: SpeechListener
    let permissionDenied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: label.1).font(.system(size: 11, weight: .bold))
                Text(label.0)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded)).kerning(0.9)
            }
            .foregroundStyle(label.2)

            Text(message)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.card)
                .shadow(color: Palette.shadow, radius: 14, y: 6)
        )
        .animation(.easeInOut(duration: 0.22), value: call.phase)
    }

    private var label: (String, String, Color) {
        switch call.phase {
        case .loading:   return ("WAKING UP", "hourglass", Palette.amber)
        case .listening: return ("LISTENING", "waveform", Palette.skyDeep)
        case .thinking:  return ("THINKING", "sparkles", Palette.amber)
        case .speaking:  return ("MIRA IS TALKING", "speaker.wave.2.fill", Palette.skyDeep)
        case .failed:    return ("SOMETHING WENT WRONG", "exclamationmark.triangle.fill", Palette.alert)
        case .idle:      return (permissionDenied ? "MICROPHONE IS OFF" : "MIRA IS READY",
                                 permissionDenied ? "mic.slash.fill" : "waveform",
                                 permissionDenied ? Palette.alert : Palette.skyDeep)
        }
    }

    private var message: String {
        switch call.phase {
        case .loading(let message): return message
        case .listening:
            return listener.partialText.isEmpty ? "I'm listening…" : listener.partialText
        case .thinking:  return "Give me a second."
        case .speaking:  return call.liveMiraText.isEmpty ? "…" : call.liveMiraText
        case .failed(let message): return message
        case .idle:
            return permissionDenied
                ? "Turn the microphone on in Settings so we can talk."
                : "“What would you like to focus on today?”"
        }
    }
}

/// Opening prompts. Tapping one sends it as if it had been spoken.
private struct Starters: View {
    @ObservedObject var call: CallViewModel

    private let options: [(String, String, Color)] = [
        ("Plan my day", "Help me plan my day.", Palette.powder),
        ("Help me think", "Help me think something through.", Palette.peach),
        ("Quick question", "I have a quick question.", Palette.butterDeep)
    ]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(options, id: \.0) { option in
                Button { call.send(option.1) } label: {
                    Text(option.0)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(Capsule().fill(option.2))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
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

    private var spoken: [ChatMessage] { call.transcript.filter { $0.role != .system } }

    var body: some View {
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
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .onChange(of: call.transcript.count) { _, _ in
                withAnimation { proxy.scrollTo(call.transcript.last?.id, anchor: .bottom) }
            }
            .onChange(of: call.liveMiraText) { _, _ in
                withAnimation { proxy.scrollTo("live", anchor: .bottom) }
            }
            .onChange(of: listener.partialText) { _, _ in
                withAnimation { proxy.scrollTo("partial", anchor: .bottom) }
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
            MiraFace(phase: .idle, level: 0)
            Text("Mira")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.ink)
            Text("Pick a model to get started.\nShe runs entirely on this phone.")
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
            Text("Or put mira.mdlo in Files ▸ On My iPhone ▸ Mira\nand reopen the app.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.inkFaint)
                .padding(.bottom, 26)
        }
    }
}
