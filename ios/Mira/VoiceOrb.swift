import SwiftUI

/// The centre of the app: a soft pink orb that compresses and expands.
///
/// Driven by a timeline rather than repeating animations, so a phase change
/// never leaves a `repeatForever` running against a stale value — the scale is
/// a pure function of the clock and the current state.
struct VoiceOrb: View {
    let phase: CallViewModel.Phase
    /// 0…1 microphone level, only meaningful while listening.
    let level: Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isListening: Bool { phase == .listening }
    private var isSpeaking: Bool { phase == .speaking }
    private var isThinking: Bool { phase == .thinking }
    private var isBusy: Bool { isListening || isSpeaking || isThinking }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let beat = self.beat(at: timeline.date)
            ZStack {
                // Halo rings, each trailing the one inside it so the orb reads
                // as breathing outward rather than simply changing size.
                ForEach(0..<3, id: \.self) { ring in
                    let delay = Double(ring) * 0.12
                    let spread = 1 + CGFloat(ring) * 0.16
                    Circle()
                        .fill(ring == 0 ? Palette.sherbet.opacity(0.55)
                                        : Palette.sherbet.opacity(0.28 - Double(ring) * 0.09))
                        .frame(width: 168, height: 168)
                        .scaleEffect(spread * self.scale(at: beat - delay))
                        .blur(radius: 2 + CGFloat(ring) * 3)
                }

                Circle()
                    .fill(
                        RadialGradient(colors: coreColors,
                                       center: .init(x: 0.38, y: 0.32),
                                       startRadius: 4, endRadius: 110)
                    )
                    .frame(width: 168, height: 168)
                    .scaleEffect(self.scale(at: beat))
                    .shadow(color: Palette.hotPink.opacity(0.35), radius: 26, y: 10)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5)
                            .scaleEffect(self.scale(at: beat))
                    )

                Image(systemName: glyph)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: Palette.deepRose.opacity(0.35), radius: 6, y: 2)
            }
            .frame(width: 240, height: 240)
            .animation(.easeInOut(duration: 0.35), value: isBusy)
        }
        .accessibilityHidden(true)
    }

    private var coreColors: [Color] {
        switch phase {
        case .listening: return [Palette.hotPink, Palette.deepRose]
        case .thinking:  return [Palette.lilac, Palette.hotPink.opacity(0.85)]
        case .speaking:  return [Palette.sherbet, Palette.hotPink]
        case .failed:    return [Palette.sherbet.opacity(0.7), Palette.inkFaint]
        default:         return [Palette.sherbet, Palette.hotPink.opacity(0.9)]
        }
    }

    private var glyph: String {
        switch phase {
        case .listening: return "waveform"
        case .thinking:  return "ellipsis"
        case .speaking:  return "hand.raised.fill"
        case .failed:    return "exclamationmark"
        default:         return "mic.fill"
        }
    }

    private func beat(at date: Date) -> Double {
        reduceMotion ? 0 : date.timeIntervalSinceReferenceDate
    }

    /// Idle breathes slowly, thinking flutters, speaking pulses in time with
    /// speech, and listening follows the microphone directly.
    private func scale(at beat: Double) -> CGFloat {
        if isListening {
            let clamped = CGFloat(min(max(level, 0), 1))
            return 0.94 + clamped * 0.34
        }
        let (period, amplitude): (Double, CGFloat) = {
            switch phase {
            case .thinking: return (0.9, 0.045)
            case .speaking: return (1.4, 0.075)
            case .failed:   return (3.0, 0.010)
            default:        return (4.2, 0.030)
            }
        }()
        let wave = sin(beat * 2 * .pi / period)
        return 1 + amplitude * CGFloat(wave)
    }
}
