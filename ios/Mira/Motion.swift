import SwiftUI

/// The app's shared motion.
///
/// Everything here is driven from a `TimelineView` rather than a repeating
/// animation. A `repeatForever` keeps running against whatever value it
/// captured, so a state change mid-cycle leaves it animating something stale;
/// a timeline recomputes from the clock every frame and simply stops when the
/// view goes away. It also means reduce-motion is one `paused:` flag rather
/// than a special case in every animation.

/// Three dots rising and falling in turn, for a wait with no progress to
/// report. Model loading takes as long as it takes and there is nothing
/// honest to put in a bar, so this says "working" and nothing more.
struct LoadingDots: View {
    var tint: Color = Palette.skyDeep
    var size: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: size * 0.7) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(tint)
                        .frame(width: size, height: size)
                        .opacity(0.45 + lift(t, index) * 0.55)
                        .offset(y: -lift(t, index) * size * 0.9)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// 0…1, each dot a third of a cycle behind the one before it. Raised to a
    /// power so a dot spends most of the cycle down and lifts briefly, which
    /// reads as a bounce rather than a wave.
    private func lift(_ t: Double, _ index: Int) -> Double {
        guard !reduceMotion else { return 0 }
        let phase = (t * 1.25 - Double(index) * 0.18).truncatingRemainder(dividingBy: 1)
        let wave = max(0, sin(phase * .pi))
        return pow(wave, 2.2)
    }
}

/// A ring that expands out of the talk button and fades, on a loop.
///
/// Two of them, half a cycle apart, so there is always one mid-flight. This
/// is the only thing on screen that says the microphone is open at the moment
/// you have not started speaking yet.
struct PulseRings: View {
    var tint: Color
    var diameter: CGFloat
    /// Rings per second. Speech is faster, which matches how she moves.
    var rate: Double = 0.8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate * rate
            ZStack {
                ForEach(0..<2, id: \.self) { index in
                    let phase = (t + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .strokeBorder(tint.opacity((1 - phase) * 0.45), lineWidth: 2.5)
                        .frame(width: diameter * (1 + CGFloat(phase) * 0.75),
                               height: diameter * (1 + CGFloat(phase) * 0.75))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Shrinks a control slightly while it is held.
///
/// iOS buttons feel dead without this, and a plain `.buttonStyle(.plain)` —
/// which every control here needs, to keep its own shape — removes the system
/// press feedback along with the system look.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}

/// A slow drift of soft blobs behind everything.
///
/// Barely visible on purpose: enough that the screen is never completely
/// still, not enough to compete with Mira or to be noticed as an effect.
struct DriftingBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Blob {
        let x: CGFloat, y: CGFloat, size: CGFloat, rate: Double, phase: Double
    }

    private static let blobs: [Blob] = [
        Blob(x: 0.18, y: 0.22, size: 0.55, rate: 0.045, phase: 0.0),
        Blob(x: 0.86, y: 0.34, size: 0.42, rate: 0.037, phase: 2.1),
        Blob(x: 0.30, y: 0.78, size: 0.48, rate: 0.052, phase: 4.3),
        Blob(x: 0.78, y: 0.88, size: 0.36, rate: 0.041, phase: 1.2)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.addFilter(.blur(radius: 60))
                for blob in Self.blobs {
                    let drift = t * blob.rate + blob.phase
                    let dx = CGFloat(sin(drift)) * size.width * 0.06
                    let dy = CGFloat(cos(drift * 1.3)) * size.height * 0.04
                    let d = size.width * blob.size
                    let rect = CGRect(x: blob.x * size.width - d / 2 + dx,
                                      y: blob.y * size.height - d / 2 + dy,
                                      width: d, height: d)
                    context.fill(Path(ellipseIn: rect),
                                 with: .color(Palette.sky.opacity(0.10)))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Fades and lifts a view in when it first appears.
///
/// Used on the screens you land on rather than on every row: an app where
/// everything animates in is slower to use, not livelier.
struct RiseIn: ViewModifier {
    var delay: Double = 0

    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85)
                    .delay(delay)) { shown = true }
            }
    }
}

extension View {
    func riseIn(delay: Double = 0) -> some View {
        modifier(RiseIn(delay: delay))
    }
}
