import SwiftUI

/// Mira: a soft, fluffy, free-form shape.
///
/// No mouth. The silhouette itself is the expression — it breathes when idle,
/// swells toward you while listening, and deforms in speech rhythm when she
/// talks. A drawn mouth would fight that; without one, every state has to be
/// carried by shape, eyes and colour, which is what makes her read as a
/// creature rather than a face on a ball.
///
/// Two things decide whether she reads as fluffy or spiky, and both are about
/// the strands rather than the outline: their proportions, and whether they
/// curl. Long, thin, straight ones are spines however many you draw. Short,
/// wide, blurred ones that bend sideways are fluff. So they are drawn in
/// layers — a soft haze furthest out, denser texture close in — each strand a
/// curve rather than a line.
///
/// Drawn in a `Canvas` rather than stacked shapes: this is several hundred
/// strokes per frame, which is fine imperatively and would not be as views.
struct MiraFace: View {
    let phase: CallViewModel.Phase
    /// 0…1 microphone level, only meaningful while listening.
    let level: Float
    /// The most room she may take. Overridable so the screens where she
    /// shares the view with something else can cap her lower than the talk
    /// screen does.
    var height: CGFloat = MiraFace.canvasHeight

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Set when she's tapped. She reacts for a moment, then settles.
    @State private var pokedAt: Date?

    private var isListening: Bool { phase == .listening }
    private var isSpeaking: Bool { phase == .speaking }
    private var isThinking: Bool { phase == .thinking }

    private static let core = Color(red: 1.00, green: 0.988, blue: 0.973)
    private static let mid = Color(red: 1.00, green: 0.937, blue: 0.878)
    private static let edge = Color(red: 0.996, green: 0.855, blue: 0.769)

    /// The most drawing area she will take. A cap rather than a fixed height:
    /// the frame is flexible below it, so on a small phone she gives room
    /// back to the caption and the controls instead of pushing them off.
    static let canvasHeight: CGFloat = 380

    /// The body as a fraction of the space available, chosen so that the body
    /// plus the longest strand plus the float still fits. The outer fur band
    /// reaches 24% past the rim, so 0.5 / 1.24 is the largest body that never
    /// clips; this backs off from that to leave room for stroke width and the
    /// bob.
    private static let bodyFraction: CGFloat = 0.375

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let now = timeline.date
            let t = reduceMotion ? 0 : now.timeIntervalSinceReferenceDate
            let poke = pokeStrength(at: now)
            let wobble = wobbleAmount(poke: poke)
            let churn = t * churnRate

            Canvas { context, size in
                let span: CGFloat = min(size.width, size.height)
                let centre = CGPoint(x: size.width / 2,
                                     y: size.height / 2 + bob(at: t))
                let base: CGFloat = span * Self.bodyFraction * (1 + poke * 0.06)
                let outline = blob(centre: centre, radius: base, churn: churn, wobble: wobble)

                // A wide soft halo, so she sits in light rather than on top of it.
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 30))
                    layer.fill(outline, with: .color(Palette.sky.opacity(0.26)))
                }

                for band in Self.furLayers {
                    fur(band, in: &context, centre: centre,
                        radius: base, churn: churn, wobble: wobble)
                }

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
                    layer.addFilter(.blur(radius: 9))
                    layer.stroke(outline, with: .color(Self.edge.opacity(0.85)), lineWidth: 16)
                }

                // A last pass over the rim. Fur behind the body alone leaves a
                // clean arc where the fill ends; these break it, so the edge
                // never resolves into a line.
                fur(Self.topFuzz, in: &context, centre: centre,
                    radius: base, churn: churn, wobble: wobble)

                blush(in: &context, centre: centre, radius: base)
                eyes(in: &context, centre: centre, radius: base, t: t, poke: poke)
            }
            .frame(minHeight: 190, maxHeight: height)
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
            if isListening { return 0.40 + CGFloat(min(max(level, 0), 1)) * 0.80 }
            if isSpeaking { return 0.85 }
            if isThinking { return 0.62 }
            if case .failed = phase { return 0.22 }
            return 0.38
        }()
        amount += poke * 0.8
        return amount
    }

    /// How far the rim deviates from a circle at one angle.
    ///
    /// Three low harmonics, each drifting at its own rate so the shape never
    /// repeats visibly. Low is the whole point: a high harmonic puts many
    /// small lobes around the rim, and small lobes are points. Three slow ones
    /// give a few broad swells instead, which is what a soft body does.
    ///
    /// Every term is its own annotated constant on purpose. Written as one
    /// summed expression mixing CGFloat and Double, this defeated the type
    /// checker — `cos` alone is ambiguous between two overloads.
    private func deviation(angle: Double, churn: Double) -> Double {
        let first: Double = 0.072 * sin(2 * angle + churn)
        let second: Double = 0.046 * sin(3 * angle - churn * 1.3)
        let third: Double = 0.021 * sin(5 * angle + churn * 0.7)
        return first + second + third
    }

    /// The rim radius at one angle.
    private func rim(angle: Double, radius: CGFloat,
                     churn: Double, wobble: CGFloat) -> CGFloat {
        let offset: CGFloat = CGFloat(deviation(angle: angle, churn: churn))
        return radius * (1 + wobble * offset)
    }

    /// A closed organic outline, smoothed through midpoints so there are no
    /// corners at the samples.
    private func blob(centre: CGPoint, radius: CGFloat,
                      churn: Double, wobble: CGFloat) -> Path {
        let samples = 72
        var points: [CGPoint] = []
        points.reserveCapacity(samples)

        for index in 0..<samples {
            let angle: Double = Double(index) / Double(samples) * 2 * .pi
            let r: CGFloat = rim(angle: angle, radius: radius,
                                 churn: churn, wobble: wobble)
            let x: CGFloat = centre.x + CGFloat(cos(angle)) * r
            let y: CGFloat = centre.y + CGFloat(sin(angle)) * r
            points.append(CGPoint(x: x, y: y))
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

    // MARK: - Fur

    /// One band of strands. Furthest out is longest, widest, faintest and most
    /// blurred; closest in is short, dense and nearly sharp. Reading the three
    /// bands top to bottom is reading the profile of the fluff.
    private struct FurLayer {
        let count: Int
        /// Strand length as a fraction of the radius.
        let minLength: Double
        let maxLength: Double
        let minWidth: CGFloat
        let maxWidth: CGFloat
        let minAlpha: Double
        let maxAlpha: Double
        let blur: CGFloat
        /// How far a strand bends, in radians. The outer ones bend most.
        let curl: Double
        /// Offsets the hash, so the bands don't sit on each other's strands.
        let seedOffset: Double
    }

    private static let furLayers: [FurLayer] = [
        FurLayer(count: 90, minLength: 0.13, maxLength: 0.24,
                 minWidth: 3.0, maxWidth: 6.0, minAlpha: 0.10, maxAlpha: 0.24,
                 blur: 6.0, curl: 0.34, seedOffset: 0),
        FurLayer(count: 130, minLength: 0.07, maxLength: 0.15,
                 minWidth: 2.2, maxWidth: 4.2, minAlpha: 0.20, maxAlpha: 0.40,
                 blur: 2.6, curl: 0.24, seedOffset: 500),
        FurLayer(count: 150, minLength: 0.035, maxLength: 0.085,
                 minWidth: 1.6, maxWidth: 3.0, minAlpha: 0.28, maxAlpha: 0.52,
                 blur: 1.0, curl: 0.16, seedOffset: 1000)
    ]

    /// Drawn over the body rather than behind it, to break the rim.
    private static let topFuzz = FurLayer(count: 110, minLength: 0.03, maxLength: 0.075,
                                          minWidth: 1.8, maxWidth: 3.4,
                                          minAlpha: 0.30, maxAlpha: 0.55,
                                          blur: 1.6, curl: 0.20, seedOffset: 2000)

    /// Strands rooted just inside the rim, curving outward.
    ///
    /// Lengths, widths and angles all come from a hash of the index, so the
    /// fluff is irregular but identical frame to frame — re-randomising each
    /// frame makes it boil.
    private func fur(_ band: FurLayer, in context: inout GraphicsContext,
                     centre: CGPoint, radius: CGFloat,
                     churn: Double, wobble: CGFloat) {
        context.drawLayer { canvas in
            canvas.addFilter(.blur(radius: band.blur))
            for index in 0..<band.count {
                let seed: Double = Double(index) + band.seedOffset
                let jitter: Double = (noise(seed) - 0.5) * 0.09
                let angle: Double = Double(index) / Double(band.count) * 2 * .pi + jitter
                let edgeRadius: CGFloat = self.rim(angle: angle, radius: radius,
                                                   churn: churn, wobble: wobble)

                let lengthSpan: Double = band.maxLength - band.minLength
                let lengthFactor: Double = band.minLength + noise(seed * 3.1) * lengthSpan
                let length: CGFloat = radius * CGFloat(lengthFactor)
                let innerFactor: Double = 0.90 + noise(seed * 7.7) * 0.07
                let inner: CGFloat = edgeRadius * CGFloat(innerFactor)
                let outer: CGFloat = edgeRadius + length

                // The strand bends: its tip sits at a different angle from its
                // root, and the control point between them is offset part of
                // the way. That curve is what separates fluff from a spine.
                let sway: Double = sin(churn * 1.4 + seed * 0.35) * 0.035
                let bend: Double = (noise(seed * 4.3) - 0.5) * band.curl
                let tipAngle: Double = angle + sway + bend
                let midAngle: Double = angle + sway + bend * 0.35
                let midRadius: CGFloat = (inner + outer) / 2

                let startX: CGFloat = centre.x + CGFloat(cos(angle)) * inner
                let startY: CGFloat = centre.y + CGFloat(sin(angle)) * inner
                let midX: CGFloat = centre.x + CGFloat(cos(midAngle)) * midRadius
                let midY: CGFloat = centre.y + CGFloat(sin(midAngle)) * midRadius
                let tipX: CGFloat = centre.x + CGFloat(cos(tipAngle)) * outer
                let tipY: CGFloat = centre.y + CGFloat(sin(tipAngle)) * outer

                var strand = Path()
                strand.move(to: CGPoint(x: startX, y: startY))
                strand.addQuadCurve(to: CGPoint(x: tipX, y: tipY),
                                    control: CGPoint(x: midX, y: midY))

                let pale: Bool = noise(seed * 2.3) > 0.42
                let tint: Color = pale ? Self.core : Self.edge
                let alphaSpan: Double = band.maxAlpha - band.minAlpha
                let alpha: Double = band.minAlpha + noise(seed * 5.9) * alphaSpan
                let widthSpan: CGFloat = band.maxWidth - band.minWidth
                let thickness: CGFloat = band.minWidth + CGFloat(noise(seed * 1.7)) * widthSpan

                canvas.stroke(strand,
                              with: .color(tint.opacity(alpha)),
                              style: StrokeStyle(lineWidth: thickness, lineCap: .round))
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
            layer.addFilter(.blur(radius: 11))
            for side in [-1.0, 1.0] as [CGFloat] {
                let width: CGFloat = radius * 0.32
                let height: CGFloat = radius * 0.18
                let x: CGFloat = centre.x + side * radius * 0.52 - width / 2
                let y: CGFloat = centre.y + radius * 0.26
                let rect = CGRect(x: x, y: y, width: width, height: height)
                layer.fill(Path(ellipseIn: rect), with: .color(Palette.cheek.opacity(0.34)))
            }
        }
    }

    /// Two eyes and nothing else. Without a mouth they carry the whole
    /// expression, so they get an iris in the theme colour and two
    /// catch-lights rather than being dots.
    private func eyes(in context: inout GraphicsContext, centre: CGPoint,
                      radius: CGFloat, t: Double, poke: CGFloat) {
        let open: CGFloat = blink(at: t)
        let wide: Bool = poke > 0.05 || isListening
        let width: CGFloat = radius * (wide ? 0.33 : 0.30)
        let height: CGFloat = radius * (wide ? 0.46 : 0.41) * open
        let idleX: CGFloat = CGFloat(sin(t / 2.6)) * radius * 0.012
        let idleY: CGFloat = CGFloat(cos(t / 3.7)) * radius * 0.008
        let driftX: CGFloat = isThinking ? radius * 0.02 : idleX
        let driftY: CGFloat = isThinking ? -radius * 0.03 : idleY

        for side in [-1.0, 1.0] as [CGFloat] {
            let x: CGFloat = centre.x + side * radius * 0.32
            let y: CGFloat = centre.y - radius * 0.05

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
