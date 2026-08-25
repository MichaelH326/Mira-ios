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
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.11),
                                    Color(red: 0.10, green: 0.09, blue: 0.18)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if model == nil {
                ImportPrompt(showImporter: $showImporter)
            } else {
                CallView(call: call,
                         permissionDenied: $permissionDenied,
                         showSettings: $showSettings)
            }
        }
        .preferredColorScheme(.dark)
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

// MARK: - Settings

private struct SettingsView: View {
    @ObservedObject var call: CallViewModel
    @Binding var model: ModelLocator.Source?
    @Binding var showImporter: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Model") {
                    LabeledContent("Source",
                                   value: (model?.isBundled ?? false) ? "Built into the app" : "Imported")
                    LabeledContent("Details", value: call.modelDescription)
                    LabeledContent("Voice", value: call.speaker.describedVoice)
                    LabeledContent("Storage used", value: ModelLocator.diskUsageDescription())
                }

                Section {
                    Button("Replace with a different model…") { showImporter = true; dismiss() }
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
                } footer: {
                    Text("Mira runs entirely on this device. Nothing you say leaves the phone.")
                }

                Section("Conversation") {
                    Toggle("Keep listening after Mira replies", isOn: $call.handsFree)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Onboarding

private struct ImportPrompt: View {
    @Binding var showImporter: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "waveform.circle")
                .font(.system(size: 76, weight: .thin))
                .foregroundStyle(.white.opacity(0.9))
            Text("Mira")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("No model found in this build.\nAdd **mira.mdlo** to the app target, or import one now.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.65))
                .padding(.horizontal, 40)
            Button {
                showImporter = true
            } label: {
                Text("Choose model file")
                    .font(.headline)
                    .padding(.horizontal, 28).padding(.vertical, 14)
                    .background(Capsule().fill(.white.opacity(0.15)))
                    .foregroundStyle(.white)
            }
            Spacer()
            Text("Or put mira.mdlo in Files ▸ On My iPhone ▸ Mira\nand reopen the app.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.bottom, 30)
        }
    }
}

// MARK: - Call

private struct CallView: View {
    @ObservedObject var call: CallViewModel
    @Binding var permissionDenied: Bool
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            TranscriptView(call: call)
            statusLine
            controls
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Text("Mira").font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(call.modelDescription.isEmpty ? "on this device" : call.modelDescription)
                    .font(.caption).foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
        }
        .overlay(alignment: .trailing) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.trailing, 22)
            .accessibilityLabel("Settings")
        }
        .padding(.top, 16).padding(.bottom, 10)
    }

    private var statusLine: some View {
        Group {
            switch call.phase {
            case .loading(let message):
                Label(message, systemImage: "hourglass")
            case .listening:
                Label(call.listener.partialText.isEmpty ? "Listening…" : call.listener.partialText,
                      systemImage: "mic.fill")
            case .thinking:
                Label("Thinking…", systemImage: "ellipsis.bubble")
            case .speaking:
                Label("Mira's talking — tap to jump in", systemImage: "speaker.wave.2.fill")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            case .idle:
                Label(permissionDenied ? "Microphone access is off — enable it in Settings"
                                       : "Tap to talk",
                      systemImage: permissionDenied ? "mic.slash" : "hand.tap")
            }
        }
        .font(.callout)
        .foregroundStyle(.white.opacity(0.75))
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.2), value: call.phase)
    }

    private var controls: some View {
        HStack(spacing: 34) {
            Button { call.reset() } label: {
                controlIcon("arrow.counterclockwise", tint: .white.opacity(0.7))
            }
            .accessibilityLabel("Start a new conversation")

            TalkButton(call: call, disabled: permissionDenied)

            Button { call.endCall() } label: {
                controlIcon("xmark", tint: .red.opacity(0.85))
            }
            .accessibilityLabel("End call")
        }
        .padding(.bottom, 34)
    }

    private func controlIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 20, weight: .medium))
            .frame(width: 52, height: 52)
            .background(Circle().fill(.white.opacity(0.10)))
            .foregroundStyle(tint)
    }
}

/// Big central button: pulses with your voice while listening.
private struct TalkButton: View {
    @ObservedObject var call: CallViewModel
    let disabled: Bool
    @State private var pulse = false

    private var isListening: Bool { call.phase == .listening }
    private var isSpeaking: Bool { call.phase == .speaking }

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
                    .fill(isListening ? Color.green.opacity(0.28) : Color.white.opacity(0.14))
                    .frame(width: 96, height: 96)
                    .scaleEffect(isListening ? 1 + CGFloat(call.listener.audioLevel) * 0.35 : 1)
                    .animation(.easeOut(duration: 0.12), value: call.listener.audioLevel)

                if isSpeaking {
                    Circle().stroke(.white.opacity(0.35), lineWidth: 2)
                        .frame(width: 110, height: 110)
                        .scaleEffect(pulse ? 1.08 : 0.96)
                        .opacity(pulse ? 0.2 : 0.7)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                }

                Image(systemName: isSpeaking ? "hand.raised.fill"
                                             : (isListening ? "waveform" : "mic.fill"))
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .disabled(disabled)
        .onAppear { pulse = true }
        .accessibilityLabel(isListening ? "Stop talking" : (isSpeaking ? "Interrupt Mira" : "Talk to Mira"))
    }
}

// MARK: - Transcript

private struct TranscriptView: View {
    @ObservedObject var call: CallViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(call.transcript.filter { $0.role != .system }) { message in
                        Bubble(text: message.text, isMira: message.role == .assistant)
                            .id(message.id)
                    }
                    if !call.liveMiraText.isEmpty {
                        Bubble(text: call.liveMiraText, isMira: true).id("live")
                    }
                    if case .listening = call.phase, !call.listener.partialText.isEmpty {
                        Bubble(text: call.listener.partialText, isMira: false)
                            .opacity(0.55).id("partial")
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
            }
            .onChange(of: call.transcript.count) { _, _ in
                withAnimation { proxy.scrollTo(call.transcript.last?.id, anchor: .bottom) }
            }
            .onChange(of: call.liveMiraText) { _, _ in
                withAnimation { proxy.scrollTo("live", anchor: .bottom) }
            }
        }
    }
}

private struct Bubble: View {
    let text: String
    let isMira: Bool

    var body: some View {
        HStack {
            if !isMira { Spacer(minLength: 40) }
            Text(text)
                .foregroundStyle(.white.opacity(isMira ? 0.95 : 0.85))
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isMira ? Color.white.opacity(0.13) : Color.blue.opacity(0.42))
                )
            if isMira { Spacer(minLength: 40) }
        }
    }
}
