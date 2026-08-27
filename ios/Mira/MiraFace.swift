import SwiftUI

/// Mira herself.
///
/// A chibi character rather than a face on a ball: the head is a squircle, not
/// a circle, which is most of why the old orb read as an orb. Hair takes the
/// theme's accent, so choosing a colour scheme recolours her too.
///
/// Everything is a function of the clock and the current phase, from one
/// `TimelineView`. Repeating animations were the alternative and they strand
/// themselves against a stale phase the moment the state changes.
struct MiraFace: View {
    let phase: CallViewModel.Phase
    /// 0…1 microphone level, only meaningful while listening.
    let level: Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Set when she's tapped. She reacts for a moment, then settles.
    @State private var pokedAt: Date?

    private let headWidth: CGFloat = 148
    private let headHeight: CGFloat = 136

    private static let skin = Color(red: 1.00, green: 0.937, blue: 0.898)

    private var isListening: Bool { phase == .listening }
    private var isSpeaking: Bool { phase == .speaking }
    private var isThinking: Bool { phase == .thinking }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let now = timeline.date
            let t = reduceMotion ? 0 : now.timeIntervalSinceReferenceDate
            let poke = pokeStrength(at: now)

            ZStack {
                groundShadow(at: t)
                sparkles(at: t)

                ZStack {
                    body(at: t)
                    backHair
                    head(at: t, poke: poke)
                    sideHair
                    ahoge(at: t)
                }
                .rotationEffect(.degrees(tilt(at: t)), anchor: .bottom)
                .offset(y: bob(at: t))
                .scaleEffect(x: 1 + poke * 0.10, y: 1 - poke * 0.10, anchor: .bottom)
            }
            .frame(width: 268, height: 250)
            .contentShape(Rectangle())
            .onTapGesture { pokedAt = Date() }
        }
        .accessibilityLabel("Mira")
        .accessibilityHint("Tap to say hello")
    }

    // MARK: - Parts

    private func groundShadow(at t: Double) -> some View {
        Ellipse()
            .fill(Palette.shadow)
            .frame(width: 116 - CGFloat(abs(sin(t / 1.7))) * 10, height: 16)
            .blur(radius: 7)
            .offset(y: 108)
    }

    private func body(at t: Double) -> some View {
        // A small rounded torso, deliberately half the head's width: the big
        // head to little body ratio is what makes a chibi read as one.
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(
                LinearGradient(colors: [Palette.sky, Palette.skyDeep],
                               startPoint: .top, endPoint: .bottom)
            )
            .frame(width: 96, height: 74)
            .overlay(
                // Collar
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 46, height: 12)
                    .offset(y: -26)
            )
            .offset(y: 74)
    }

    private var backHair: some View {
        RoundedRectangle(cornerRadius: 66, style: .continuous)
            .fill(Palette.hair)
            .frame(width: headWidth + 22, height: headHeight + 18)
            .offset(y: 4)
    }

    private func head(at t: Double, poke: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 62, style: .continuous)
        return shape
            .fill(
                RadialGradient(colors: [.white, Self.skin],
                               center: UnitPoint(x: 0.36, y: 0.30),
                               startRadius: 4, endRadius: headWidth * 0.8)
            )
            .frame(width: headWidth, height: headHeight)
            .overlay(bangs.clipShape(shape))
            .overlay(features(at: t, poke: poke))
            .shadow(color: Palette.shadowSoft, radius: 10, y: 6)
    }

    /// A fringe built from three overlapping sweeps rather than one hand-tuned
    /// path — far easier to keep symmetrical, and it clips to the head.
    private var bangs: some View {
        ZStack {
            Ellipse()
                .fill(Palette.hair)
                .frame(width: headWidth + 10, height: 104)
                .offset(y: -58)
            Ellipse()
                .fill(Palette.hair)
                .frame(width: 74, height: 92)
                .offset(x: -44, y: -34)
            Ellipse()
                .fill(Palette.hair)
                .frame(width: 74, height: 92)
                .offset(x: 44, y: -34)
            // A lighter sheen across the fringe, the way hair is drawn in cel
            // shading — a single band, not a gradient.
            Capsule()
                .fill(Palette.hairLight.opacity(0.55))
                .frame(width: 86, height: 9)
                .offset(y: -50)
        }
    }

    private var sideHair: some View {
        HStack(spacing: headWidth - 16) {
            Capsule().fill(Palette.hair).frame(width: 26, height: 92)
            Capsule().fill(Palette.hair).frame(width: 26, height: 92)
        }
        .offset(y: 22)
    }

    /// The cowlick. It sways on its own and flicks when she's thinking, which
    /// does more for "alive" than any amount of easing on the body.
    private func ahoge(at t: Double) -> some View {
        let sway = sin(t * (isThinking ? 3.4 : 1.5)) * (isThinking ? 16 : 8)
        return AhogeShape()
            .stroke(Palette.hair, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            .frame(width: 44, height: 40)
            .rotationEffect(.degrees(sway), anchor: .bottomLeading)
            .offset(x: 10, y: -84)
    }

    @ViewBuilder
    private func features(at t: Double, poke: CGFloat) -> some View {
        let blinking = blink(at: t)
        let widened = poke > 0.05 || isListening

        ZStack {
            // Blush
            HStack(spacing: 62) {
                blush
                blush
            }
            .offset(y: 24)

            // Brows — small, but they carry more expression than the eyes do.
            HStack(spacing: 44) {
                brow.rotationEffect(.degrees(browAngle), anchor: .center)
                brow.rotationEffect(.degrees(-browAngle), anchor: .center)
            }
            .offset(y: -30 + browLift)

            // Eyes
            HStack(spacing: 30) {
                eye(blink: blinking, widened: widened, at: t)
                eye(blink: blinking, widened: widened, at: t)
            }
            .offset(y: 2)

            mouth(at: t, poke: poke).offset(y: 42)
        }
    }

    private var blush: some View {
        Ellipse()
            .fill(Palette.cheek.opacity(0.40))
            .frame(width: 26, height: 15)
            .blur(radius: 4)
    }

    private var brow: some View {
        Capsule()
            .fill(Palette.hair)
            .frame(width: 22, height: 5)
    }

    private var browAngle: Double {
        switch phase {
        case .thinking: return 9
        case .failed:   return -11
        default:        return 0
        }
    }

    private var browLift: CGFloat {
        isListening ? -4 : (isSpeaking ? -2 : 0)
    }

    private func eye(blink: CGFloat, widened: Bool, at t: Double) -> some View {
        // Eyes drift a little when idle, so she reads as looking around rather
        // than staring through you.
        let driftX = isThinking ? 3.0 : sin(t / 2.6) * 2.0
        let driftY = isThinking ? -4.0 : cos(t / 3.7) * 1.2

        return ZStack {
            Capsule()
                .fill(Palette.eye)
                .frame(width: widened ? 30 : 27, height: widened ? 38 : 34)
            // Iris in the theme colour, so she matches the scheme
            Capsule()
                .fill(
                    LinearGradient(colors: [Palette.sky, Palette.skyDeep],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 17, height: 21)
                .offset(x: driftX, y: 4 + driftY)
            // Two catch-lights: the detail that reads as anime rather than
            // as two dots.
            Circle().fill(.white).frame(width: 9, height: 9)
                .offset(x: -6 + driftX, y: -9 + driftY)
            Circle().fill(.white.opacity(0.75)).frame(width: 4.5, height: 4.5)
                .offset(x: 6 + driftX, y: 8 + driftY)
        }
        .scaleEffect(x: 1, y: blink, anchor: .center)
    }

    private func mouth(at t: Double, poke: CGFloat) -> some View {
        let clamped = CGFloat(min(max(level, 0), 1))
        let (width, height): (CGFloat, CGFloat) = {
            if poke > 0.05 { return (26, 18) }          // a happy open smile
            switch phase {
            case .listening:
                let d = 13 + clamped * 13
                return (d, d)
            case .speaking:
                let openness = (sin(t * 11) + 1) / 2
                return (24, 6 + CGFloat(openness) * 15)
            case .thinking: return (15, 5)
            case .failed:   return (17, 5)
            default:        return (26, 9)
            }
        }()

        return RoundedRectangle(cornerRadius: min(width, height) / 2, style: .continuous)
            .fill(
                LinearGradient(colors: [Palette.amber, Palette.cheek],
                               startPoint: .top, endPoint: .bottom)
            )
            .frame(width: width, height: height)
            .animation(.easeOut(duration: 0.12), value: height)
    }

    private func sparkles(at t: Double) -> some View {
        let spots: [(CGFloat, CGFloat, CGFloat, Double)] = [
            (-112, -66, 19, 0.0),
            (108, -44, 14, 1.1),
            (96, 66, 16, 2.2),
            (-98, 52, 11, 3.0)
        ]
        return ZStack {
            ForEach(Array(spots.enumerated()), id: \.offset) { _, spot in
                let twinkle = (sin(t * 1.7 + spot.3) + 1) / 2
                Sparkle()
                    .fill(Palette.amber.opacity(0.28 + twinkle * 0.42))
                    .frame(width: spot.2, height: spot.2)
                    .scaleEffect(0.75 + CGFloat(twinkle) * 0.35)
                    .offset(x: spot.0, y: spot.1)
            }
        }
    }

    // MARK: - Motion

    /// A slow float when idle, quicker while thinking, in time with speech
    /// while speaking, and following the microphone while listening.
    private func bob(at t: Double) -> CGFloat {
        if isListening {
            return 2 - CGFloat(min(max(level, 0), 1)) * 9
        }
        let (period, amplitude): (Double, CGFloat) = {
            if isSpeaking { return (1.3, 5) }
            if isThinking { return (2.0, 3) }
            return (3.6, 6)
        }()
        return CGFloat(sin(t * 2 * .pi / period)) * amplitude
    }

    private func tilt(at t: Double) -> Double {
        guard isThinking else { return isListening ? 2 : 0 }
        return sin(t * 1.3) * 6
    }

    /// A quick blink roughly every four and a half seconds, with a
    /// double-blink — a single even blink looks mechanical.
    private func blink(at t: Double) -> CGFloat {
        guard !reduceMotion else { return 1 }
        let cycle = t.truncatingRemainder(dividingBy: 4.6)
        if cycle < 0.13 { return 0.08 }
        if cycle > 0.26 && cycle < 0.37 { return 0.12 }
        return 1
    }

    /// 1 immediately after a tap, falling to 0 over about a second.
    private func pokeStrength(at now: Date) -> CGFloat {
        guard let pokedAt, !reduceMotion else { return 0 }
        let age = now.timeIntervalSince(pokedAt)
        guard age >= 0, age < 0.9 else { return 0 }
        return CGFloat(cos(age / 0.9 * .pi / 2))
    }
}

/// The cowlick: up, over, and back down in a little hook.
struct AhogeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.maxX * 0.86, y: rect.minY + rect.height * 0.16),
                      control1: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.midY),
                      control2: CGPoint(x: rect.maxX * 0.55, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX * 0.52, y: rect.minY + rect.height * 0.40),
                      control1: CGPoint(x: rect.maxX * 1.05, y: rect.minY + rect.height * 0.28),
                      control2: CGPoint(x: rect.maxX * 0.80, y: rect.minY + rect.height * 0.46))
        return path
    }
}

/// The equaliser under Mira. Reacts to your voice while listening and idles as
/// a gentle ripple otherwise.
struct WaveBars: View {
    let level: Float
    let phase: CallViewModel.Phase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let count = 9

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 5) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(color(index))
                        .frame(width: 6, height: height(index, at: t))
                }
            }
            .frame(height: 46)
        }
        .accessibilityHidden(true)
    }

    private func color(_ index: Int) -> Color {
        // Centre bars carry the accent, edges fade to pastel.
        let distance = abs(Double(index) - Double(count - 1) / 2)
        let edge = distance / (Double(count - 1) / 2)
        return Palette.skyDeep.opacity(1 - edge * 0.60)
    }

    private func height(_ index: Int, at t: Double) -> CGFloat {
        let distance = abs(Double(index) - Double(count - 1) / 2)
        let centreBias = 1 - (distance / (Double(count - 1) / 2)) * 0.55
        let wave = (sin(t * 6 + Double(index) * 0.7) + 1) / 2

        let amplitude: Double
        switch phase {
        case .listening: amplitude = 8 + Double(min(max(level, 0), 1)) * 34
        case .speaking:  amplitude = 22
        case .thinking:  amplitude = 12
        default:         amplitude = 7
        }
        return CGFloat(max(6, (6 + wave * amplitude) * centreBias))
    }
}
