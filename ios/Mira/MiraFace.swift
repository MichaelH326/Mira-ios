import SwiftUI

/// Mira herself: a soft pastel face that blinks, breathes, and moves her mouth
/// while she talks.
///
/// Everything is a function of the clock and the current phase, driven from a
/// single `TimelineView`. Repeating animations were the alternative and they
/// strand themselves against a stale phase the moment the state changes.
struct MiraFace: View {
    let phase: CallViewModel.Phase
    /// 0…1 microphone level, only meaningful while listening.
    let level: Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size: CGFloat = 198

    private var isListening: Bool { phase == .listening }
    private var isSpeaking: Bool { phase == .speaking }
    private var isThinking: Bool { phase == .thinking }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let breath = self.breath(at: t)

            ZStack {
                // Ambient glow
                Circle()
                    .fill(
                        RadialGradient(colors: [Palette.sky.opacity(0.38), .clear],
                                       center: .center, startRadius: 40, endRadius: 150)
                    )
                    .frame(width: size * 1.5, height: size * 1.5)
                    .scaleEffect(breath * 1.02)
                    .blur(radius: 12)

                // The face
                Circle()
                    .fill(
                        RadialGradient(
                            colors: faceColors,
                            center: UnitPoint(x: 0.34, y: 0.28),
                            startRadius: 6, endRadius: size * 0.78
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5)
                    )
                    .shadow(color: Palette.shadow, radius: 26, y: 12)
                    .scaleEffect(breath)

                features(at: t)
                    .scaleEffect(breath)

                sparkles(at: t)
            }
            .frame(width: size * 1.42, height: size * 1.18)
        }
        .accessibilityHidden(true)
    }

    private var faceColors: [Color] {
        switch phase {
        case .listening: return [.white.opacity(0.95), Palette.powder, Palette.sky]
        case .thinking:  return [.white.opacity(0.95), Palette.butterDeep, Palette.powder]
        case .speaking:  return [.white.opacity(0.95), Palette.peach, Palette.sky.opacity(0.75)]
        case .failed:    return [.white.opacity(0.9), Palette.peach.opacity(0.7), Palette.inkFaint.opacity(0.5)]
        default:         return [.white.opacity(0.95), Palette.peach, Palette.powder]
        }
    }

    // MARK: - Face

    @ViewBuilder
    private func features(at t: Double) -> some View {
        let blink = self.blink(at: t)
        let tilt = isThinking ? sin(t * 1.4) * 5 : 0

        ZStack {
            // Blush
            HStack(spacing: 96) {
                cheek
                cheek
            }
            .offset(y: 26)

            // Eyes
            HStack(spacing: 52) {
                eye(blink: blink)
                eye(blink: blink)
            }
            .offset(y: -14)

            mouth(at: t)
                .offset(y: 44)
        }
        .rotationEffect(.degrees(tilt), anchor: .center)
    }

    private var cheek: some View {
        Ellipse()
            .fill(Palette.cheek.opacity(0.45))
            .frame(width: 34, height: 20)
            .blur(radius: 7)
    }

    private func eye(blink: CGFloat) -> some View {
        ZStack {
            Capsule()
                .fill(Palette.eye)
                .frame(width: 21, height: 27)
            // Catch-light: the thing that makes it read as anime rather than a dot
            Circle()
                .fill(Color.white)
                .frame(width: 7, height: 7)
                .offset(x: -4.5, y: -7)
            Circle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 3.5, height: 3.5)
                .offset(x: 4, y: 5)
        }
        .scaleEffect(x: 1, y: blink, anchor: .center)
    }

    /// Mouth shape carries the state more than anything else does.
    private func mouth(at t: Double) -> some View {
        let clamped = CGFloat(min(max(level, 0), 1))
        let (width, height): (CGFloat, CGFloat) = {
            switch phase {
            case .listening:
                // A small "o" that opens as you get louder
                let d = 17 + clamped * 15
                return (d, d)
            case .speaking:
                let openness = (sin(t * 11) + 1) / 2
                return (30, 7 + CGFloat(openness) * 19)
            case .thinking:
                return (20, 6)
            case .failed:
                return (22, 6)
            default:
                return (38, 11)
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

    // MARK: - Motion

    /// Slow when idle, quicker while thinking, in time with speech while
    /// speaking, and following the microphone directly while listening.
    private func breath(at t: Double) -> CGFloat {
        if isListening {
            return 0.97 + CGFloat(min(max(level, 0), 1)) * 0.16
        }
        let (period, amplitude): (Double, CGFloat) = {
            if isSpeaking { return (1.3, 0.035) }
            if isThinking { return (0.95, 0.022) }
            return (4.4, 0.026)
        }()
        return 1 + amplitude * CGFloat(sin(t * 2 * .pi / period))
    }

    /// A quick blink roughly every four seconds, plus a double-blink.
    private func blink(at t: Double) -> CGFloat {
        guard !reduceMotion else { return 1 }
        let cycle = t.truncatingRemainder(dividingBy: 4.6)
        if cycle < 0.13 { return 0.08 }
        if cycle > 0.26 && cycle < 0.37 { return 0.12 }
        return 1
    }

    private func sparkles(at t: Double) -> some View {
        let spots: [(CGFloat, CGFloat, CGFloat, Double)] = [
            (-104, -74, 20, 0.0),
            (98, -52, 14, 1.1),
            (86, 74, 17, 2.2),
            (-92, 60, 11, 3.0)
        ]
        return ZStack {
            ForEach(Array(spots.enumerated()), id: \.offset) { _, spot in
                let twinkle = (sin(t * 1.7 + spot.3) + 1) / 2
                Sparkle()
                    .fill(Palette.sky.opacity(0.34 + twinkle * 0.46))
                    .frame(width: spot.2, height: spot.2)
                    .scaleEffect(0.75 + CGFloat(twinkle) * 0.35)
                    .offset(x: spot.0, y: spot.1)
            }
        }
    }
}

/// The equaliser under Mira's face. Reacts to your voice while listening and
/// idles as a gentle ripple otherwise.
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
