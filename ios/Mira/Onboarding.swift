import SwiftUI

/// First-run personalisation.
///
/// Mira is on screen the whole way through and recolours as you choose, so
/// every choice is previewed on the thing it changes rather than described in
/// a row of text.
struct OnboardingView: View {
    @ObservedObject var call: CallViewModel
    /// Called when the last step is done, or when it's skipped.
    var onFinish: () -> Void

    @AppStorage(Prefs.themeKey) private var theme = Theme.butter.rawValue
    @AppStorage(Prefs.nameKey) private var yourName = ""
    @AppStorage(Prefs.engineKey) private var engine = "edge"
    @AppStorage(Prefs.handsFreeKey) private var handsFree = true

    @State private var step = 0
    @FocusState private var nameFocused: Bool

    private let lastStep = 3

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                MiraFace(phase: previewPhase, level: 0, height: 240)
                Spacer(minLength: 4)
                card
                controls
            }
        }
        .animation(.easeInOut(duration: 0.28), value: step)
    }

    /// Mira demonstrates the step being configured.
    private var previewPhase: CallViewModel.Phase {
        switch step {
        case 2: return .speaking
        case 3: return .listening
        default: return .idle
        }
    }

    private var header: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer()
            Button("Skip") { onFinish() }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
    }

    @ViewBuilder
    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch step {
            case 0: nameStep
            case 1: themeStep
            case 2: voiceStep
            default: handsFreeStep
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Palette.card)
                .shadow(color: Palette.shadow, radius: 14, y: 6)
        )
        .padding(.horizontal, 18)
    }

    private var title: String {
        switch step {
        case 0: return "Hello, I'm Mira"
        case 1: return "Pick a mood"
        case 2: return "How I sound"
        default: return "How we talk"
        }
    }

    private var subtitle: String {
        switch step {
        case 0: return "What should I call you? You can leave this blank."
        case 1: return "This colours the whole app — and me."
        case 2: return "The on-device voice works with no signal. Edge sounds better but sends what I say to Microsoft to be spoken."
        default: return "Hands-free keeps listening after I reply, so it feels like a call rather than a walkie-talkie."
        }
    }

    // MARK: - Steps

    private var nameStep: some View {
        TextField("Your name", text: $yourName)
            .focused($nameFocused)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(Capsule().fill(Palette.powder.opacity(0.35)))
    }

    private var themeStep: some View {
        HStack(spacing: 10) {
            ForEach(Theme.allCases) { option in
                Button { theme = option.rawValue } label: {
                    VStack(spacing: 7) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [option.groundTop, option.groundBottom],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(width: 44, height: 44)
                            Circle().fill(option.accent).frame(width: 19, height: 19)
                        }
                        .overlay(
                            Circle().strokeBorder(
                                theme == option.rawValue ? option.accentDeep : .clear,
                                lineWidth: 2.5)
                                .frame(width: 52, height: 52)
                        )
                        Text(option.name.split(separator: " ").first.map(String.init) ?? option.name)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme == option.rawValue ? Palette.ink : Palette.inkFaint)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    private var voiceStep: some View {
        VStack(spacing: 9) {
            voiceChoice("On my phone", detail: "Private, works offline", value: "kokoro")
            voiceChoice("Microsoft Edge", detail: "Better voices, needs a connection", value: "edge")
        }
    }

    private func voiceChoice(_ name: String, detail: String, value: String) -> some View {
        Button { engine = value } label: {
            HStack(spacing: 12) {
                Image(systemName: engine == value ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(engine == value ? Palette.skyDeep : Palette.inkFaint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(engine == value ? Palette.powder.opacity(0.45) : Palette.powder.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
    }

    private var handsFreeStep: some View {
        Toggle(isOn: $handsFree) {
            Text("Keep listening after I reply")
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink)
        }
        .tint(Palette.skyDeep)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(0...lastStep, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? Palette.skyDeep : Palette.inkFaint.opacity(0.35))
                        .frame(width: index == step ? 20 : 7, height: 7)
                }
            }

            Button {
                if step < lastStep {
                    nameFocused = false
                    step += 1
                } else {
                    call.applyVoiceEngine()
                    call.handsFree = handsFree
                    onFinish()
                }
            } label: {
                Text(step < lastStep ? "Next" : "Start talking")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(LinearGradient(colors: [Palette.sky, Palette.skyDeep],
                                                 startPoint: .leading, endPoint: .trailing))
                            .shadow(color: Palette.shadow, radius: 12, y: 5)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
        }
        .padding(.top, 16)
        .padding(.bottom, 22)
    }
}
