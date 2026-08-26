import SwiftUI

/// Preferences that persist. Everything here does something — a toggle that
/// only looks like it works is worse than no toggle, particularly for the
/// privacy ones.
enum Prefs {
    static let voiceKey = "mira.voice.speaker"
    static let speedKey = "mira.voice.speed"
    static let hapticsKey = "mira.haptics"
    static let handsFreeKey = "mira.handsFree"
    static let engineKey = "mira.voice.engine"
    static let edgeVoiceKey = "mira.voice.edgeName"
}

struct SettingsView: View {
    @ObservedObject var call: CallViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.voiceKey) private var speaker = 0
    @AppStorage(Prefs.speedKey) private var speed = 1.0
    @AppStorage(Prefs.hapticsKey) private var haptics = true
    @AppStorage(Prefs.engineKey) private var engine = "edge"
    @AppStorage(Prefs.edgeVoiceKey) private var edgeVoice = "Rosa"

    @State private var showImporter = false
    @State private var exporting = false

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        voiceCard
                        privacyCard
                        modelCard
                        aboutCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 34)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            RoundedIconButton(system: "arrow.left", tint: Palette.ink) { dismiss() }
                .accessibilityLabel("Back")
            Spacer()
            Text("Settings")
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.ink)
            Spacer()
            Color.clear.frame(width: 46, height: 46)
        }
        .padding(.top, 10)
    }

    // MARK: - Cards

    private var voiceCard: some View {
        Card(icon: "speaker.wave.2.fill", tint: Palette.powder,
             title: "Voice", subtitle: engine == "edge" ? "MICROSOFT EDGE · ONLINE" : "ON-DEVICE SYNTHESIZER") {
            row("Engine") {
                Picker("", selection: $engine) {
                    Text("Edge (online)").tag("edge")
                    Text("On-device").tag("kokoro")
                }
                .pickerStyle(.menu)
                .tint(Palette.skyInk)
                .onChange(of: engine) { _, _ in call.applyVoiceEngine() }
            }
            Divider().overlay(Palette.powder)
            if engine == "edge" {
                row("Edge voice") {
                    TextField("Rosa", text: $edgeVoice)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                        .onSubmit { call.applyVoiceEngine() }
                }
                Divider().overlay(Palette.powder)
            }
            if engine != "edge" {
                row("Mira's voice") {
                    Picker("", selection: $speaker) {
                        ForEach(0..<6, id: \.self) { index in
                            Text("Voice \(index + 1)").tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Palette.skyInk)
                }
                Divider().overlay(Palette.powder)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Speaking speed")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(Palette.inkSoft)
                    Spacer()
                    Text(String(format: "%.1fx", speed))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                }
                Slider(value: $speed, in: 0.7...1.4, step: 0.05)
                    .tint(Palette.skyDeep)
            }
            Text(engine == "edge"
                 ? "Edge voices are synthesized by Microsoft, so this needs a connection and the text of Mira's replies is sent to them. If it can't be reached, Mira switches to the on-device voice for the rest of the session."
                 : "Voices come from the bundled Kokoro model — these are its first six English speakers, not separate personalities.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacyCard: some View {
        Card(icon: "lock.shield.fill", tint: Palette.peach,
             title: "Privacy", subtitle: "NOTHING LEAVES THIS PHONE") {
            row("Keep listening after Mira replies") {
                Toggle("", isOn: $call.handsFree).labelsHidden().tint(Palette.skyDeep)
            }
            Divider().overlay(Palette.powder)
            row("Haptic feedback") {
                Toggle("", isOn: $haptics).labelsHidden().tint(Palette.skyDeep)
            }
            Divider().overlay(Palette.powder)
            Button {
                exporting = true
            } label: {
                HStack {
                    Text("Export saved chats")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(call.sessions.sessions.isEmpty ? Palette.inkFaint : Palette.skyDeep)
            }
            .buttonStyle(.plain)
            .disabled(call.sessions.sessions.isEmpty)
            Text("Speech, generation and the voice all run on this device. There is no account and no server to turn off.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $exporting) {
            if let url = call.sessions.exportFile() {
                ShareSheet(items: [url])
            }
        }
    }

    private var modelCard: some View {
        Card(icon: "cpu.fill", tint: Palette.butterDeep,
             title: "Model", subtitle: "RUNNING LOCALLY") {
            info("Details", call.modelDescription.isEmpty ? "—" : call.modelDescription)
            Divider().overlay(Palette.powder)
            info("Voice engine", call.speaker.describedVoice)
            Divider().overlay(Palette.powder)
            info("Storage used", ModelLocator.diskUsageDescription())
            Divider().overlay(Palette.powder)
            Button("Free extracted cache") {
                ModelLocator.clearExtractedCache()
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.skyDeep)
            .buttonStyle(.plain)
        }
    }

    private var aboutCard: some View {
        Card(icon: "info.circle.fill", tint: Palette.powder,
             title: "About", subtitle: "APP INFORMATION") {
            info("Version", Bundle.main.appVersion)
            Divider().overlay(Palette.powder)
            info("Built on", "llama.cpp · sherpa-onnx · Kokoro")
        }
    }

    // MARK: - Pieces

    private func row<Content: View>(_ label: String,
                                    @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Palette.inkSoft)
            Spacer(minLength: 10)
            trailing()
        }
    }

    private func info(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Palette.inkSoft)
            Spacer(minLength: 10)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct Card<Content: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let content: Content

    init(icon: String, tint: Color, title: String, subtitle: String,
         @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint).frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.skyInk)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.ink)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded)).kerning(0.7)
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer()
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Palette.card)
                .shadow(color: Palette.shadow, radius: 12, y: 5)
        )
    }
}

/// Hands the exported chats file to the system share sheet.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension Bundle {
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
