import SwiftUI

/// Mira: a soft, fluffy, free-form shape.
///
/// No mouth. The silhouette itself is the expression — it breathes when idle,
/// swells toward you while listening, and deforms in speech rhythm when she
/// talks. A drawn mouth would fight that; without one, every state has to be
/// carried by shape, eyes and colour, which is what makes her read as a
/// creature rather than a face on a ball.
///
/// Drawn in a `Canvas` rather than stacked shapes: the fur is ~170 tapered
/// strands per frame, which is fine imperatively and would not be as views.
struct MiraFace: View {
    let phase: CallViewModel.Phase
    /// 0…1 microphone level, only meaningful while listening.
    let level: Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Set when she's tapped. She reacts for a moment, then settles.
    @State private var pokedAt: Date?

    private var isListening: Bool { phase == .listening }
    private var isSpeaking: Bool { phase == .speaking }
    private var isThinking: Bool { phase == .thinking }

    private static let core = Color(red: 1.00, green: 0.988, blue: 0.973)
    private static let mid = Color(red: 1.00, green: 0.937, blue: 0.878)
    private static let edge = Color(red: 0.996, green: 0.855, blue: 0.769)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let now = timeline.date
            let t = reduceMotion ? 0 : now.timeIntervalSinceReferenceDate
            let poke = pokeStrength(at: now)
            let wobble = wobbleAmount(poke: poke)
            let churn = t * churnRate

            Canvas { context, size in
                let centre = CGPoint(x: size.width / 2,
                                     y: size.height / 2 + bob(at: t))
                let base = min(size.width, size.height) * 0.33 * (1 + poke * 0.06)
                let outline = blob(centre: centre, radius: base, churn: churn, wobble: wobble)

                // A wide soft halo, so she sits in light rather than on top of it.
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 26))
                    layer.fill(outline, with: .color(Palette.sky.opacity(0.28)))
                }

                fur(in: &context, centre: centre, radius: base, churn: churn, wobble: wobble)

                context.fill(
                    outline,
                    with: .radialGradient(
                        Gradient(colors: [Self.core, Self.mid, Self.edge]),
                        center: CGPoint(x: centre.x - base * 0.22, y: centre.y - base * 0.30),
                        startRadius: 2, endRadius: base * 1.5)
                )

                // The softest edge: a blurred rim inside the silhouette, which
                // is what stops it reading as a hard vector shape.
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 7))
                    layer.stroke(outline, with: .color(Self.edge.opacity(0.85)), lineWidth: 12)
                }

                blush(in: &context, centre: centre, radius: base)
                eyes(in: &context, centre: centre, radius: base, t: t, poke: poke)
            }
            .frame(height: 260)
            .contentShape(Rectangle())
            .onTapGesture { pokedAt = Date() }
        }
        .accessibilityLabel("Mira")
        .accessibilityHint("Tap to say hello")
    }

    // MARK: - Silhouette

    /// How fast the shape churns. Speech is the fastest, which is what sells
    /// "she's talking" with no mouth to move.
    private var churnRate: Double {
        if isSpeaking { return 2.6 }
        if isThinking { return 1.5 }
        if isListening { return 1.0 }
        return 0.45
    }

    /// How far it deviates from a circle.
    private func wobbleAmount(poke: CGFloat) -> CGFloat {
        var amount: CGFloat = {
            if isListening { return 0.45 + CGFloat(min(max(level, 0), 1)) * 0.95 }
            if isSpeaking { return 1.0 }
            if isThinking { return 0.7 }
            if case .failed = phase { return 0.25 }
            return 0.42
        }()
        amount += poke * 0.9
        return amount
    }

    /// A closed organic outline: three harmonics summed around the circle,
    /// each drifting at its own rate so the shape never repeats visibly.
    /// Smoothed through midpoints so there are no corners at the samples.
    private func blob(centre: CGPoint, radius: CGFloat,
                      churn: Double, wobble: CGFloat) -> Path {
        let samples = 72
        var points: [CGPoint] = []
        points.reserveCapacity(samples)

        for index in 0..<samples {
            let angle = Double(index) / Double(samples) * 2 * .pi
            let deviation =
                0.075 * sin(3 * angle + churn) +
                0.048 * sin(5 * angle - churn * 1.35) +
                0.030 * sin(7 * angle + churn * 0.7) +
                0.020 * sin(11 * angle - churn * 0.5)
            let r = radius * (1 + wobble * CGFloat(deviation))
            points.append(CGPoint(x: centre.x + cos(angle) * r,
                                  y: centre.y + sin(angle) * r))
        }

        var path = Path()
        guard points.count > 2 else { return path }
        let first = midpoint(points[points.count - 1], points[0])
        path.move(to: first)
        for index in 0..<points.count {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            path.addQuadCurve(to: midpoint(current, next), control: current)
        }
        path.closeSubpath()
        return path
    }

    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    /// Tapered strands radiating from just inside the rim. Lengths and angles
    /// come from a hash of the index, so the fluff is irregular but identical
    /// frame to frame — random per frame would boil.
    private func fur(in context: inout GraphicsContext, centre: CGPoint,
                     radius: CGFloat, churn: Double, wobble: CGFloat) {
        let strands = 170
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 0.7))
            for index in 0..<strands {
                let seed = Double(index)
                let jitter = (noise(seed) - 0.5) * 0.055
                let angle = seed / Double(strands) * 2 * .pi + jitter

                let deviation =
                    0.075 * sin(3 * angle + churn) +
                    0.048 * sin(5 * angle - churn * 1.35) +
                    0.030 * sin(7 * angle + churn * 0.7) +
                    0.020 * sin(11 * angle - churn * 0.5)
                let rim = radius * (1 + wobble * CGFloat(deviation))

                let length = radius * CGFloat(0.10 + noise(seed * 3.1) * 0.20)
                let inner = rim * CGFloat(0.86 + noise(seed * 7.7) * 0.08)
                let sway = sin(churn * 1.6 + seed * 0.35) * 0.03

                let start = CGPoint(x: centre.x + cos(angle) * inner,
                                    y: centre.y + sin(angle) * inner)
                let end = CGPoint(x: centre.x + cos(angle + sway) * (rim + length),
                                  y: centre.y + sin(angle + sway) * (rim + length))

                var strand = Path()
                strand.move(to: start)
                strand.addLine(to: end)

                let pale = noise(seed * 2.3) > 0.45
                layer.stroke(
                    strand,
                    with: .color((pale ? Self.core : Self.edge)
                        .opacity(0.35 + noise(seed * 5.9) * 0.45)),
                    style: StrokeStyle(lineWidth: 0.7 + CGFloat(noise(seed * 1.7)) * 1.1,
                                       lineCap: .round)
                )
            }
        }
    }

    /// Deterministic 0…1 from an index. Not good noise; good enough for fluff.
    private func noise(_ value: Double) -> Double {
        let x = sin(value * 12.9898) * 43758.5453
        return x - x.rounded(.down)
    }

    // MARK: - Face

    private func blush(in context: inout GraphicsContext, centre: CGPoint, radius: CGFloat) {
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 9))
            for side in [-1.0, 1.0] {
                let rect = CGRect(x: centre.x + CGFloat(side) * radius * 0.46 - 17,
                                  y: centre.y + radius * 0.20,
                                  width: 34, height: 19)
                layer.fill(Path(ellipseIn: rect), with: .color(Palette.cheek.opacity(0.34)))
            }
        }
    }

    /// Two eyes and nothing else. Without a mouth they carry the whole
    /// expression, so they get an iris in the theme colour and two
    /// catch-lights rather than being dots.
    private func eyes(in context: inout GraphicsContext, centre: CGPoint,
                      radius: CGFloat, t: Double, poke: CGFloat) {
        let open = blink(at: t)
        let wide = poke > 0.05 || isListening
        let width = radius * (wide ? 0.24 : 0.21)
        let height = radius * (wide ? 0.32 : 0.28) * open
        let driftX = isThinking ? radius * 0.02 : CGFloat(sin(t / 2.6)) * radius * 0.012
        let driftY = isThinking ? -radius * 0.03 : CGFloat(cos(t / 3.7)) * radius * 0.008

        for side in [-1.0, 1.0] {
            let x = centre.x + CGFloat(side) * radius * 0.30
            let y = centre.y - radius * 0.06

            let socket = CGRect(x: x - width / 2, y: y - height / 2,
                                width: width, height: height)
            context.fill(Path(roundedRect: socket, cornerRadius: width / 2),
                         with: .color(Palette.eye))

            guard height > width * 0.5 else { continue }   // mid-blink: skip detail

            let irisSize = width * 0.62
            let iris = CGRect(x: x - irisSize / 2 + driftX,
                              y: y - irisSize / 2 + height * 0.10 + driftY,
                              width: irisSize, height: irisSize)
            context.fill(Path(ellipseIn: iris),
                         with: .linearGradient(Gradient(colors: [Palette.sky, Palette.skyDeep]),
                                               startPoint: CGPoint(x: iris.minX, y: iris.minY),
                                               endPoint: CGPoint(x: iris.maxX, y: iris.maxY)))

            let big = width * 0.34
            context.fill(
                Path(ellipseIn: CGRect(x: x - width * 0.26 + driftX,
                                       y: y - height * 0.26 + driftY,
                                       width: big, height: big)),
                with: .color(.white))
            let small = width * 0.17
            context.fill(
                Path(ellipseIn: CGRect(x: x + width * 0.14 + driftX,
                                       y: y + height * 0.18 + driftY,
                                       width: small, height: small)),
                with: .color(.white.opacity(0.75)))
        }
    }

    // MARK: - Motion

    private func bob(at t: Double) -> CGFloat {
        if isListening {
            return 2 - CGFloat(min(max(level, 0), 1)) * 8
        }
        let (period, amplitude): (Double, CGFloat) = {
            if isSpeaking { return (1.3, 4) }
            if isThinking { return (2.0, 3) }
            return (3.8, 6)
        }()
        return CGFloat(sin(t * 2 * .pi / period)) * amplitude
    }

    /// A quick blink roughly every four and a half seconds, with a
    /// double-blink — an evenly spaced one looks mechanical.
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
