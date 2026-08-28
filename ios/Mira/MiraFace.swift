import SwiftUI

/// Mira: a soft, free-form creature in one pastel colour, with hair.
///
/// No mouth. The silhouette is the expression — it breathes when idle, swells
/// toward you while listening, and deforms in speech rhythm when she talks.
/// Without a mouth, shape and eyes and hair carry every state, which is what
/// makes her read as a creature rather than a face on a ball.
///
/// She is one hue in three steps rather than a blend of colours: a near-white
/// lit side, the pastel itself, and a deeper shade for the hair and the shadow
/// it casts. That restraint is most of what makes her look designed. The hue
/// comes from the theme, so picking a scheme recolours her.
///
/// The hair is drawn as soft spikes: tufts with curved sides and a blunted
/// tip, a few behind the body and more in front, swaying on their own clock.
/// Sharp spikes would read as spiny — the blunting is the whole trick — and
/// the body's fluff is deliberately quieter than it was, because the hair now
/// carries the character and two competing textures read as noise.
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
    private var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    /// The most drawing area she will take. A cap rather than a fixed height:
    /// the frame is flexible below it, so on a small phone she gives room
    /// back to the caption and the controls instead of pushing them off.
    static let canvasHeight: CGFloat = 400

    /// The body as a fraction of the space available, chosen so that the body
    /// plus the tallest hair tuft plus the float still fits. Hair reaches 34%
    /// past the rim, so 0.5 / 1.34 is the largest body that never clips; this
    /// backs off from that for stroke width and the bob.
    private static let bodyFraction: CGFloat = 0.355

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
                    layer.addFilter(.blur(radius: 32))
                    layer.fill(outline, with: .color(Palette.furDeep.opacity(0.30)))
                }

                // Hair behind the body reads as depth: you see the far side of
                // her head past the near side.
                hair(Self.backTufts, in: &context, centre: centre, radius: base,
                     churn: churn, wobble: wobble, t: t, tint: Palette.furDeep.opacity(0.75))

                for band in Self.furLayers {
                    fur(band, in: &context, centre: centre,
                        radius: base, churn: churn, wobble: wobble)
                }

                context.fill(
                    outline,
                    with: .radialGradient(
                        Gradient(colors: [Palette.furLight, Palette.furMid]),
                        center: CGPoint(x: centre.x - base * 0.26, y: centre.y - base * 0.34),
                        startRadius: base * 0.05, endRadius: base * 1.25)
                )

                // The softest edge: a blurred rim inside the silhouette, which
                // is what stops it reading as a hard vector shape.
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 10))
                    layer.stroke(outline, with: .color(Palette.furMid.opacity(0.9)), lineWidth: 16)
                }

                // A last pass over the rim. Fur behind the body alone leaves a
                // clean arc where the fill ends; these break it.
                fur(Self.topFuzz, in: &context, centre: centre,
                    radius: base, churn: churn, wobble: wobble)

                context.fill(hairline(centre: centre, radius: base, churn: churn,
                                      wobble: wobble, t: t),
                             with: .color(Palette.furDeep))
                hair(Self.frontTufts, in: &context, centre: centre, radius: base,
                     churn: churn, wobble: wobble, t: t, tint: Palette.furDeep)
                // The shadow the hair casts on her forehead. Without it the
                // hair looks stuck on rather than growing out.
                hairShadow(in: &context, centre: centre, radius: base)

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
        if isLoading { return 1.1 }
        if isListening { return 1.0 }
        return 0.45
    }

    /// How far it deviates from a circle.
    private func wobbleAmount(poke: CGFloat) -> CGFloat {
        var amount: CGFloat = {
            if isListening { return 0.40 + CGFloat(min(max(level, 0), 1)) * 0.80 }
            if isSpeaking { return 0.85 }
            if isThinking { return 0.62 }
            if isLoading { return 0.50 }
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

    // MARK: - Hair

    /// One tuft of hair: where it sits, how long, how wide at the base, and
    /// how far it leans. Angles are in turns clockwise from straight up, so
    /// they read as clock positions rather than radians.
    private struct Tuft {
        let turn: Double        // 0 = straight up, ±0.25 = the sides
        let length: Double      // as a fraction of the body radius
        let width: Double       // half-width at the base, in turns
        let lean: Double        // tip offset, in turns
        let sway: Double        // how much it moves on its own
    }

    /// Behind the body: a few long ones showing past her sides, which is what
    /// gives the head depth instead of a flat disc.
    private static let backTufts: [Tuft] = [
        Tuft(turn: -0.315, length: 0.26, width: 0.030, lean: -0.070, sway: 0.9),
        Tuft(turn: -0.250, length: 0.22, width: 0.028, lean: -0.055, sway: 1.2),
        Tuft(turn: -0.075, length: 0.20, width: 0.026, lean: -0.020, sway: 1.0),
        Tuft(turn:  0.075, length: 0.20, width: 0.026, lean:  0.020, sway: 1.1),
        Tuft(turn:  0.250, length: 0.22, width: 0.028, lean:  0.055, sway: 1.2),
        Tuft(turn:  0.315, length: 0.26, width: 0.030, lean:  0.070, sway: 0.8)
    ]

    /// In front. Narrow relative to their spacing, so the tips stay separate —
    /// wide ones merge into a single lump and the whole head reads as wearing
    /// a cap. The lengths are deliberately uneven, and the long off-centre one
    /// is the cowlick: it does most of the work of making her look like a
    /// character rather than a shape.
    private static let frontTufts: [Tuft] = [
        Tuft(turn: -0.290, length: 0.16, width: 0.026, lean: -0.070, sway: 1.4),
        Tuft(turn: -0.232, length: 0.27, width: 0.025, lean: -0.052, sway: 1.1),
        Tuft(turn: -0.174, length: 0.19, width: 0.024, lean: -0.038, sway: 1.3),
        Tuft(turn: -0.116, length: 0.34, width: 0.026, lean: -0.030, sway: 0.9),
        Tuft(turn: -0.058, length: 0.22, width: 0.024, lean: -0.012, sway: 1.2),
        Tuft(turn:  0.000, length: 0.29, width: 0.025, lean:  0.006, sway: 1.0),
        Tuft(turn:  0.058, length: 0.18, width: 0.024, lean:  0.020, sway: 1.3),
        Tuft(turn:  0.116, length: 0.31, width: 0.026, lean:  0.034, sway: 0.9),
        Tuft(turn:  0.174, length: 0.20, width: 0.024, lean:  0.048, sway: 1.2),
        Tuft(turn:  0.232, length: 0.25, width: 0.025, lean:  0.062, sway: 1.1),
        Tuft(turn:  0.290, length: 0.15, width: 0.026, lean:  0.078, sway: 1.4)
    ]

    /// How far around the top the solid hairline reaches, in turns.
    private static let hairlineReach: Double = 0.30

    /// The solid band of hair across the top of her head.
    ///
    /// Spikes alone don't read as hair — they read as spikes. What makes it
    /// hair is a continuous mass at the roots with the spikes rising out of
    /// it, so this is drawn first and the tufts sit on top: outer edge just
    /// past the rim, inner edge cutting across her forehead.
    private func hairline(centre: CGPoint, radius: CGFloat,
                          churn: Double, wobble: CGFloat, t: Double) -> Path {
        let samples = 40
        let reach = Self.hairlineReach
        let dip: Double = sin(t * 0.7) * 0.008        // the fringe breathes

        var path = Path()
        // Out along the top edge.
        for index in 0...samples {
            let turn: Double = -reach + Double(index) / Double(samples) * reach * 2
            let angle: Double = turn * 2 * .pi - .pi / 2
            let r: CGFloat = rim(angle: angle, radius: radius,
                                 churn: churn, wobble: wobble) * 1.035
            let p = point(centre, angle, r)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        // And back along the inner edge, dipping lowest at the middle so the
        // fringe comes to a soft point over her face.
        for index in stride(from: samples, through: 0, by: -1) {
            let turn: Double = -reach + Double(index) / Double(samples) * reach * 2
            let angle: Double = turn * 2 * .pi - .pi / 2
            // 1 in the middle, 0 at the ends.
            let centreness: Double = cos(turn / reach * .pi / 2)
            let depth: Double = 0.90 - centreness * (0.20 + dip)
            let r: CGFloat = rim(angle: angle, radius: radius,
                                 churn: churn, wobble: wobble) * CGFloat(depth)
            path.addLine(to: point(centre, angle, r))
        }
        path.closeSubpath()
        return path
    }

    /// A soft spike: two curves from the base out to a blunted tip.
    ///
    /// The blunting is the whole trick. Two curves meeting at a point give a
    /// thorn; carrying the tip across a short flat between them gives hair.
    private func hair(_ tufts: [Tuft], in context: inout GraphicsContext,
                      centre: CGPoint, radius: CGFloat, churn: Double,
                      wobble: CGFloat, t: Double, tint: Color) {
        for (index, tuft) in tufts.enumerated() {
            let drift: Double = sin(t * 0.9 + Double(index) * 1.7) * 0.012 * tuft.sway
            let flick: Double = isThinking ? sin(t * 3.2 + Double(index)) * 0.010 : 0
            let lean: Double = tuft.lean + drift + flick

            // Straight up is -pi/2 in screen space, and turns go clockwise.
            let axis: Double = tuft.turn * 2 * .pi - .pi / 2
            let leftBase: Double = axis - tuft.width * 2 * .pi
            let rightBase: Double = axis + tuft.width * 2 * .pi
            let tipAxis: Double = axis + lean * 2 * .pi

            // Rooted inside the hairline so each tuft grows out of the mass
            // rather than balancing on the rim.
            let root: CGFloat = 0.86
            let leftR: CGFloat = rim(angle: leftBase, radius: radius,
                                     churn: churn, wobble: wobble) * root
            let rightR: CGFloat = rim(angle: rightBase, radius: radius,
                                      churn: churn, wobble: wobble) * root
            let tipR: CGFloat = rim(angle: tipAxis, radius: radius,
                                    churn: churn, wobble: wobble)
                * (1 + CGFloat(tuft.length))

            let left = point(centre, leftBase, leftR)
            let right = point(centre, rightBase, rightR)
            // The blunt tip: two points a little either side of the axis.
            let tipSpread: Double = tuft.width * 0.30 * 2 * .pi
            let tipA = point(centre, tipAxis - tipSpread, tipR)
            let tipB = point(centre, tipAxis + tipSpread, tipR)
            // Control points bow the sides outward, which is what stops it
            // reading as a triangle.
            let bow: CGFloat = 0.55
            let ctrlA = point(centre, leftBase - tuft.width * 0.6 * 2 * .pi,
                              leftR + (tipR - leftR) * bow)
            let ctrlB = point(centre, rightBase + tuft.width * 0.6 * 2 * .pi,
                              rightR + (tipR - rightR) * bow)

            var strand = Path()
            strand.move(to: left)
            strand.addQuadCurve(to: tipA, control: ctrlA)
            strand.addQuadCurve(to: tipB, control: point(centre, tipAxis, tipR * 1.03))
            strand.addQuadCurve(to: right, control: ctrlB)
            strand.closeSubpath()

            context.fill(strand, with: .color(tint))
        }
    }

    /// Where the hair meets the head, darkened. Blurred hard so it is a
    /// gradation and not an edge.
    private func hairShadow(in context: inout GraphicsContext,
                            centre: CGPoint, radius: CGFloat) {
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 14))
            let rect = CGRect(x: centre.x - radius * 0.80,
                              y: centre.y - radius * 0.96,
                              width: radius * 1.60, height: radius * 0.44)
            layer.fill(Path(ellipseIn: rect), with: .color(Palette.furDeep.opacity(0.28)))
        }
    }

    private func point(_ centre: CGPoint, _ angle: Double, _ r: CGFloat) -> CGPoint {
        CGPoint(x: centre.x + CGFloat(cos(angle)) * r,
                y: centre.y + CGFloat(sin(angle)) * r)
    }

    // MARK: - Fur

    /// One band of strands around the rim. Quieter than it was: the hair now
    /// carries the character, and two loud textures read as noise.
    private struct FurLayer {
        let count: Int
        let minLength: Double
        let maxLength: Double
        let minWidth: CGFloat
        let maxWidth: CGFloat
        let minAlpha: Double
        let maxAlpha: Double
        let blur: CGFloat
        let curl: Double
        let seedOffset: Double
    }

    private static let furLayers: [FurLayer] = [
        FurLayer(count: 80, minLength: 0.08, maxLength: 0.15,
                 minWidth: 3.0, maxWidth: 6.0, minAlpha: 0.10, maxAlpha: 0.22,
                 blur: 6.0, curl: 0.34, seedOffset: 0),
        FurLayer(count: 120, minLength: 0.05, maxLength: 0.10,
                 minWidth: 2.2, maxWidth: 4.2, minAlpha: 0.18, maxAlpha: 0.34,
                 blur: 2.6, curl: 0.24, seedOffset: 500)
    ]

    /// Drawn over the body rather than behind it, to break the rim.
    private static let topFuzz = FurLayer(count: 100, minLength: 0.025, maxLength: 0.06,
                                          minWidth: 1.8, maxWidth: 3.4,
                                          minAlpha: 0.22, maxAlpha: 0.42,
                                          blur: 1.6, curl: 0.20, seedOffset: 2000)

    /// Strands rooted just inside the rim, curving outward. Lengths, widths
    /// and angles come from a hash of the index, so the fluff is irregular but
    /// identical frame to frame — re-randomising each frame makes it boil.
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
                let tint: Color = pale ? Palette.furLight : Palette.furMid
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
            let y: CGFloat = centre.y + radius * 0.02

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
            if isLoading { return (1.6, 5) }
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
