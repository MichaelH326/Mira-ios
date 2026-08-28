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
/// She is hair all the way round, not a face with a fringe on it: the
/// reference is a pom, so tufts ring the whole silhouette and the body is
/// only what fills in behind them. They are soft spikes — curved sides, a
/// blunted tip — because sharp ones read as spiny, and they come in two rings
/// offset by half a step so the darker under-ring shows between the tufts of
/// the top one. Longest at the crown and shortest underneath, which is most
/// of what keeps a ring of spikes from reading as a sea urchin.
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
    /// plus the longest tuft of the outermost ring plus the float still fits.
    /// That ring roots at 0.84 of the rim and reaches 0.34 × 1.40 beyond it,
    /// so about 1.32 rim in total; this backs off from 0.5 / 1.32 for stroke
    /// width and the bob.
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

                // The far side of the coat: darker, and offset half a step so
                // it shows between the tufts in front. Darker rather than
                // translucent — a see-through layer reads as a ghost of the
                // one in front, not as depth.
                context.drawLayer { layer in
                    layer.addFilter(.colorMultiply(Color(white: 0.86)))
                    hair(Self.underCoat, in: &layer, centre: centre, radius: base,
                         churn: churn, wobble: wobble, t: t, tint: Palette.furMid)
                }

                // The ground the coat is drawn on, in the same colour as the
                // coat. Not the body — every part of it ends up under a tuft;
                // it is only here so no background shows through the gaps.
                context.fill(blob(centre: centre, radius: base * 0.90,
                                  churn: churn, wobble: wobble),
                             with: .color(Palette.furMid))

                // The coat, innermost ring first, every ring the same colour.
                //
                // What separates the layers is the shadow each one drops on
                // the one beneath: the same tufts, blurred, darkened and
                // offset down and right, drawn just before the ring itself so
                // only the part past its own edges survives. Without it a coat
                // of one flat colour is a single silhouette with no interior
                // at all — every overlap is invisible.
                for coat in Self.coats {
                    context.drawLayer { layer in
                        layer.translateBy(x: base * 0.035, y: base * 0.05)
                        layer.addFilter(.blur(radius: base * 0.05))
                        hair(coat.tufts, in: &layer, centre: centre, radius: base,
                             churn: churn, wobble: wobble, t: t,
                             tint: Palette.furDeep.opacity(0.55))
                    }
                    hair(coat.tufts, in: &context, centre: centre, radius: base,
                         churn: churn, wobble: wobble, t: t, tint: Palette.furMid)
                }

                // Fine strands over the whole coat, catching the light. The
                // tufts give the mass its shape; these give it its texture.
                for band in Self.furLayers {
                    fur(band, in: &context, centre: centre,
                        radius: base, churn: churn, wobble: wobble)
                }

                // One shading pass over the whole of her, and the only thing
                // giving her form: the coat is a single flat colour, so
                // without this she is a silhouette. Light from the upper left,
                // deepening across to the lower right, clipped to her.
                shading(in: &context, centre: centre, radius: base,
                        churn: churn, wobble: wobble)

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
        let root: Double        // fraction of the rim where it starts
        let length: Double      // as a fraction of the rim
        let width: Double       // half-width at the base, in turns
        let lean: Double        // tip offset, in turns
        let sway: Double        // how much it moves on its own
    }

    /// One layer of the coat.
    private struct Ring {
        let tufts: [Tuft]
    }

    /// She is made of hair, all the way in.
    ///
    /// Not a ball with a fringe: an actual coat, drawn as concentric rings of
    /// tufts from near her centre out past the rim, each ring long enough to
    /// reach across the next so there is no smooth ground anywhere. What you
    /// see is a hundred overlapping soft spikes, and the fill underneath
    /// exists only so no background shows between them.
    ///
    /// Every ring is the same colour — she is one flat pastel, top to bottom.
    /// What tells the layers apart is shading, not hue: each ring drops a
    /// blurred shadow onto the one beneath it before it is filled, and a
    /// single gradient over the whole mass at the end gives her form. Tinting
    /// the rings differently instead is what made her look washed out, pale
    /// in the middle and coloured only at the edge.
    private static let coats: [Ring] = [
        Ring(tufts: ring(count: 12, seed: 0, phase: 0.00,
                         root: 0.20, length: 0.34, width: 0.34)),
        Ring(tufts: ring(count: 16, seed: 300, phase: 0.35,
                         root: 0.38, length: 0.34, width: 0.34)),
        Ring(tufts: ring(count: 20, seed: 600, phase: 0.15,
                         root: 0.55, length: 0.33, width: 0.34)),
        Ring(tufts: ring(count: 24, seed: 900, phase: 0.45,
                         root: 0.70, length: 0.33, width: 0.34)),
        Ring(tufts: ring(count: 28, seed: 1200, phase: 0.20,
                         root: 0.84, length: 0.34, width: 0.34))
    ]

    /// Drawn behind everything, darker, so the mass has a far side.
    private static let underCoat: [Tuft] = ring(count: 22, seed: 1900, phase: 0.5,
                                                root: 0.80, length: 0.32, width: 0.34)

    /// One ring of tufts. `phase` offsets it by that fraction of a step.
    private static func ring(count: Int, seed: Double, phase: Double,
                             root: Double, length: Double, width: Double) -> [Tuft] {
        (0..<count).map { index in
            let step: Double = 1 / Double(count)
            let turn: Double = (Double(index) + phase) * step - 0.5
            let hash: Double = hashed(Double(index) * 1.7 + seed)
            let hash2: Double = hashed(Double(index) * 4.1 + seed)

            // 1 at the crown, 0 underneath. Hair is longest on top and
            // shortest below, and that gradient is most of what stops a ring
            // of spikes reading as a sea urchin.
            let crown: Double = (cos(turn * 2 * .pi) + 1) / 2
            // The hash term is the largest of the three on purpose. An evenly
            // stepped ring of equal spikes reads as a gear or a flower however
            // soft the tips are; neighbours differing by half their length is
            // what makes it hair.
            let scale: Double = 0.55 + crown * 0.25 + hash * 0.60

            // Everything leans the same way round, as if combed, with the
            // lean smallest where the tufts are longest.
            let lean: Double = (0.004 + hash2 * 0.010) * (turn < 0 ? -1 : 1)

            return Tuft(turn: turn,
                        root: root,
                        length: length * scale,
                        width: step * (width + hash2 * 0.22),
                        lean: lean,
                        sway: 0.8 + hash2 * 0.7)
        }
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

            let root: CGFloat = CGFloat(tuft.root)
            let reach: CGFloat = CGFloat(tuft.root + tuft.length)
            let leftR: CGFloat = rim(angle: leftBase, radius: radius,
                                     churn: churn, wobble: wobble) * root
            let rightR: CGFloat = rim(angle: rightBase, radius: radius,
                                      churn: churn, wobble: wobble) * root
            let tipR: CGFloat = rim(angle: tipAxis, radius: radius,
                                    churn: churn, wobble: wobble) * reach

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
        FurLayer(count: 90, minLength: 0.10, maxLength: 0.20,
                 minWidth: 1.6, maxWidth: 3.0, minAlpha: 0.10, maxAlpha: 0.22,
                 blur: 2.2, curl: 0.30, seedOffset: 0),
        FurLayer(count: 110, minLength: 0.08, maxLength: 0.16,
                 minWidth: 1.2, maxWidth: 2.4, minAlpha: 0.14, maxAlpha: 0.30,
                 blur: 1.0, curl: 0.22, seedOffset: 500)
    ]

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
                // Rooted anywhere from a third of the way in to just under
                // the rim, so the strands read across the whole coat rather
                // than only around its edge.
                let innerFactor: Double = 0.30 + noise(seed * 7.7) * 0.58
                let inner: CGFloat = edgeRadius * CGFloat(innerFactor)
                let outer: CGFloat = inner + length

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

    /// Light across the whole mass, clipped to it.
    ///
    /// Two halves that have to travel together: a lit crown up and to the
    /// left, and a deepening toward the lower right. Either alone reads as a
    /// smudge; together they read as a round thing under a light.
    private func shading(in context: inout GraphicsContext, centre: CGPoint,
                         radius: CGFloat, churn: Double, wobble: CGFloat) {
        // Clipped at the rim and not past it. A mask wider than the fur
        // actually reaches darkens bare background around her, which reads as
        // a smudge behind her rather than shading on her — and leaving the
        // tips beyond the rim unshaded is what makes them look backlit.
        let mass = blob(centre: centre, radius: radius,
                        churn: churn, wobble: wobble)
        let box = CGRect(x: centre.x - radius * 1.4, y: centre.y - radius * 1.4,
                         width: radius * 2.8, height: radius * 2.8)

        context.drawLayer { layer in
            layer.clip(to: mass)
            layer.fill(Path(box), with: .linearGradient(
                Gradient(colors: [Palette.furDeep.opacity(0),
                                  Palette.furDeep.opacity(0.56)]),
                startPoint: CGPoint(x: centre.x - radius * 0.5,
                                    y: centre.y - radius * 0.8),
                endPoint: CGPoint(x: centre.x + radius * 0.9,
                                  y: centre.y + radius * 1.1)))
        }

        context.drawLayer { layer in
            layer.clip(to: mass)
            layer.addFilter(.blur(radius: radius * 0.26))
            let lit = CGRect(x: centre.x - radius * 0.98, y: centre.y - radius * 1.05,
                             width: radius * 1.25, height: radius * 1.20)
            layer.fill(Path(ellipseIn: lit),
                       with: .color(Palette.furLight.opacity(0.60)))
        }
    }

    /// Deterministic 0…1 from an index. Not good noise; good enough for
    /// fluff. Static because the tuft rings are built before any instance is.
    static func hashed(_ value: Double) -> Double {
        let x = sin(value * 12.9898) * 43758.5453
        return x - x.rounded(.down)
    }

    private func noise(_ value: Double) -> Double { Self.hashed(value) }

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
