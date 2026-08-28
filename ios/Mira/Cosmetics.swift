import SwiftUI

/// Things Mira can wear.
///
/// Drawn rather than shipped as images, for the same reason she is: they have
/// to sit on an outline that changes shape every frame. A hat placed at a
/// fixed offset would float off her head the moment she wobbles, so every
/// piece is positioned against `MiraGeometry.rim` — her actual silhouette at
/// that angle, this frame — and so it rides her breathing and her bob for
/// free.
///
/// Three slots, each independent: a hat, glasses, and one extra. Adding a
/// fourth is a new enum, one more line in `MiraFace.body`, and one more row
/// in `SettingsView.lookCard`.

/// Where Mira is, right now, in the coordinates her canvas is using.
///
/// Angles are in *turns* clockwise from straight up, so they read as clock
/// positions: 0 is the top of her head, ±0.25 the sides, ±0.5 the bottom.
struct MiraGeometry {
    let centre: CGPoint
    let radius: CGFloat
    let t: Double
    /// Distance from her centre to her outline at that turn.
    let rim: (Double) -> CGFloat

    // Her face, so glasses can find the eyes rather than guess at them.
    let eyeY: CGFloat
    let eyeSpread: CGFloat
    let eyeWidth: CGFloat
    let eyeHeight: CGFloat

    /// Straight up is -pi/2 in screen space, and turns go clockwise.
    func angle(_ turn: Double) -> Double { turn * 2 * .pi - .pi / 2 }

    func point(_ turn: Double, _ r: CGFloat) -> CGPoint {
        let a: Double = angle(turn)
        return CGPoint(x: centre.x + CGFloat(cos(a)) * r,
                       y: centre.y + CGFloat(sin(a)) * r)
    }

    /// A point on her outline, scaled in or out from it.
    func onRim(_ turn: Double, _ scale: CGFloat) -> CGPoint {
        point(turn, rim(turn) * scale)
    }

    /// A band following her outline between two turns, `outer` and `inner`
    /// as multiples of the rim. The shape every hat brim and headband is
    /// built from.
    func band(from start: Double, to end: Double,
              outer: CGFloat, inner: CGFloat, samples: Int = 44) -> Path {
        var path = Path()
        for index in 0...samples {
            let turn: Double = start + (end - start) * Double(index) / Double(samples)
            let p = onRim(turn, outer)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        for index in stride(from: samples, through: 0, by: -1) {
            let turn: Double = start + (end - start) * Double(index) / Double(samples)
            path.addLine(to: onRim(turn, inner))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Hats

enum Hat: String, CaseIterable, Identifiable {
    case none, beanie, party, bow, crown, flower

    var id: String { rawValue }

    var name: String {
        switch self {
        case .none:   return "None"
        case .beanie: return "Beanie"
        case .party:  return "Party hat"
        case .bow:    return "Bow"
        case .crown:  return "Crown"
        case .flower: return "Flower"
        }
    }

    func draw(in context: inout GraphicsContext, on mira: MiraGeometry) {
        switch self {
        case .none:   break
        case .beanie: drawBeanie(&context, mira)
        case .party:  drawParty(&context, mira)
        case .bow:    drawBow(&context, mira)
        case .crown:  drawCrown(&context, mira)
        case .flower: drawFlower(&context, mira)
        }
    }

    /// A dome pulled down over the top of her head, a rolled brim along its
    /// lower edge, and a pom.
    private func drawBeanie(_ context: inout GraphicsContext, _ mira: MiraGeometry) {
        let dome = mira.band(from: -0.29, to: 0.29, outer: 1.06, inner: 0.72)
        context.fill(dome, with: .color(Palette.skyDeep))

        let brim = mira.band(from: -0.30, to: 0.30, outer: 0.84, inner: 0.68)
        context.fill(brim, with: .color(Palette.sky))

        let pomSize: CGFloat = mira.radius * 0.20
        let pomCentre = mira.onRim(0, 1.14)
        context.fill(Path(ellipseIn: CGRect(x: pomCentre.x - pomSize / 2,
                                            y: pomCentre.y - pomSize / 2,
                                            width: pomSize, height: pomSize)),
                     with: .color(Palette.card))
    }

    /// A cone standing on her crown, with stripes wrapped round it.
    private func drawParty(_ context: inout GraphicsContext, _ mira: MiraGeometry) {
        let left = mira.onRim(-0.13, 0.99)
        let right = mira.onRim(0.13, 0.99)
        let tip = mira.onRim(0, 1.62)

        var cone = Path()
        cone.move(to: left)
        cone.addLine(to: tip)
        cone.addLine(to: right)
        cone.closeSubpath()
        context.fill(cone, with: .color(Palette.amber))

        // Stripes, clipped to the cone so they stop at its sides.
        context.drawLayer { layer in
            layer.clip(to: cone)
            for step in 1...3 {
                let along: CGFloat = CGFloat(step) * 0.26
                let a = CGPoint(x: left.x + (tip.x - left.x) * along,
                                y: left.y + (tip.y - left.y) * along)
                let b = CGPoint(x: right.x + (tip.x - right.x) * along,
                                y: right.y + (tip.y - right.y) * along)
                var stripe = Path()
                stripe.move(to: a)
                stripe.addLine(to: b)
                layer.stroke(stripe, with: .color(Palette.card),
                             style: StrokeStyle(lineWidth: mira.radius * 0.055,
                                                lineCap: .round))
            }
        }

        let pomSize: CGFloat = mira.radius * 0.15
        context.fill(Path(ellipseIn: CGRect(x: tip.x - pomSize / 2, y: tip.y - pomSize / 2,
                                            width: pomSize, height: pomSize)),
                     with: .color(Palette.card))
    }

    /// Two loops and a knot, worn off to one side.
    private func drawBow(_ context: inout GraphicsContext, _ mira: MiraGeometry) {
        let knot = mira.onRim(-0.155, 1.01)
        let loop: CGFloat = mira.radius * 0.21
        let lift: CGFloat = mira.radius * 0.05

        for side in [-1.0, 1.0] as [CGFloat] {
            let cx: CGFloat = knot.x + side * loop * 0.78
            let rect = CGRect(x: cx - loop * 0.72, y: knot.y - loop * 0.62 - lift,
                              width: loop * 1.44, height: loop * 1.24)
            context.fill(Path(ellipseIn: rect), with: .color(Palette.cheek))
        }

        let knotSize: CGFloat = loop * 0.62
        context.fill(Path(ellipseIn: CGRect(x: knot.x - knotSize / 2,
                                            y: knot.y - knotSize / 2 - lift,
                                            width: knotSize, height: knotSize)),
                     with: .color(Palette.alert))
    }

    /// A band with five points, each tipped with a bead.
    private func drawCrown(_ context: inout GraphicsContext, _ mira: MiraGeometry) {
        let points = 5
        let start: Double = -0.20
        let end: Double = 0.20

        var spikes = Path()
        for index in 0..<points {
            let step: Double = (end - start) / Double(points)
            let left: Double = start + step * Double(index)
            let right: Double = left + step
            let middle: Double = (left + right) / 2
            spikes.move(to: mira.onRim(left, 1.02))
            spikes.addLine(to: mira.onRim(middle, 1.30))
            spikes.addLine(to: mira.onRim(right, 1.02))
            spikes.closeSubpath()
        }
        context.fill(spikes, with: .color(Palette.amber))
        context.fill(mira.band(from: start, to: end, outer: 1.06, inner: 0.90),
                     with: .color(Palette.amber))

        let bead: CGFloat = mira.radius * 0.055
        for index in 0..<points {
            let step: Double = (end - start) / Double(points)
            let middle: Double = start + step * (Double(index) + 0.5)
            let tip = mira.onRim(middle, 1.30)
            context.fill(Path(ellipseIn: CGRect(x: tip.x - bead, y: tip.y - bead,
                                                width: bead * 2, height: bead * 2)),
                         with: .color(Palette.card))
        }
    }

    /// Five petals and a centre, tucked at the side of her head.
    private func drawFlower(_ context: inout GraphicsContext, _ mira: MiraGeometry) {
        let anchor = mira.onRim(-0.175, 1.00)
        let petal: CGFloat = mira.radius * 0.115

        for index in 0..<5 {
            let around: Double = Double(index) / 5 * 2 * .pi
            let cx: CGFloat = anchor.x + CGFloat(cos(around)) * petal * 1.05
            let cy: CGFloat = anchor.y + CGFloat(sin(around)) * petal * 1.05
            context.fill(Path(ellipseIn: CGRect(x: cx - petal, y: cy - petal,
                                                width: petal * 2, height: petal * 2)),
                         with: .color(Palette.cheek))
        }
        let heart: CGFloat = mira.radius * 0.075
        context.fill(Path(ellipseIn: CGRect(x: anchor.x - heart, y: anchor.y - heart,
                                            width: heart * 2, height: heart * 2)),
                     with: .color(Palette.amber))
    }
}

// MARK: - Glasses

enum Glasses: String, CaseIterable, Identifiable {
    case none, round, sun, reading

    var id: String { rawValue }

    var name: String {
        switch self {
        case .none:    return "None"
        case .round:   return "Round"
        case .sun:     return "Sunglasses"
        case .reading: return "Readers"
        }
    }

    func draw(in context: inout GraphicsContext, on mira: MiraGeometry) {
        guard self != Glasses.none else { return }

        let lens: CGFloat = mira.eyeWidth * 1.34
        let tall: CGFloat = self == .round ? lens : mira.eyeHeight * 0.86
        let weight: CGFloat = mira.radius * (self == .reading ? 0.022 : 0.030)
        let frame: Color = self == .reading ? Palette.skyDeep : Palette.ink

        var bridge = Path()
        bridge.move(to: CGPoint(x: mira.centre.x - mira.eyeSpread + lens / 2,
                                y: mira.eyeY))
        bridge.addLine(to: CGPoint(x: mira.centre.x + mira.eyeSpread - lens / 2,
                                   y: mira.eyeY))
        context.stroke(bridge, with: .color(frame),
                       style: StrokeStyle(lineWidth: weight, lineCap: .round))

        for side in [-1.0, 1.0] as [CGFloat] {
            let cx: CGFloat = mira.centre.x + side * mira.eyeSpread
            let rect = CGRect(x: cx - lens / 2, y: mira.eyeY - tall / 2,
                              width: lens, height: tall)
            let shape = self == .round
                ? Path(ellipseIn: rect)
                : Path(roundedRect: rect, cornerRadius: tall * 0.34)

            if self == .sun {
                context.fill(shape, with: .color(Palette.ink.opacity(0.86)))
                // One diagonal highlight, so the lens reads as glass.
                var glint = Path()
                glint.move(to: CGPoint(x: rect.minX + lens * 0.18, y: rect.maxY - tall * 0.20))
                glint.addLine(to: CGPoint(x: rect.minX + lens * 0.62, y: rect.minY + tall * 0.18))
                context.stroke(glint, with: .color(.white.opacity(0.45)),
                               style: StrokeStyle(lineWidth: weight * 0.9, lineCap: .round))
            }
            context.stroke(shape, with: .color(frame), lineWidth: weight)

            // An arm reaching back toward her rim.
            var arm = Path()
            arm.move(to: CGPoint(x: cx + side * lens / 2, y: mira.eyeY - tall * 0.12))
            arm.addLine(to: CGPoint(x: cx + side * (lens / 2 + mira.radius * 0.22),
                                    y: mira.eyeY - tall * 0.30))
            context.stroke(arm, with: .color(frame),
                           style: StrokeStyle(lineWidth: weight, lineCap: .round))
        }
    }
}

// MARK: - Extras

enum Extra: String, CaseIterable, Identifiable {
    case none, headphones, scarf, sparkles

    var id: String { rawValue }

    var name: String {
        switch self {
        case .none:       return "None"
        case .headphones: return "Headphones"
        case .scarf:      return "Scarf"
        case .sparkles:   return "Sparkles"
        }
    }

    func draw(in context: inout GraphicsContext, on mira: MiraGeometry) {
        switch self {
        case .none:       break
        case .headphones: drawHeadphones(&context, mira)
        case .scarf:      drawScarf(&context, mira)
        case .sparkles:   drawSparkles(&context, mira)
        }
    }

    private func drawHeadphones(_ context: inout GraphicsContext, _ mira: MiraGeometry) {
        context.fill(mira.band(from: -0.26, to: 0.26, outer: 1.10, inner: 1.02),
                     with: .color(Palette.skyInk))

        for side in [-1.0, 1.0] as [Double] {
            let cup = mira.onRim(side * 0.255, 1.00)
            let w: CGFloat = mira.radius * 0.20
            let h: CGFloat = mira.radius * 0.30
            let rect = CGRect(x: cup.x - w / 2, y: cup.y - h / 2, width: w, height: h)
            context.fill(Path(roundedRect: rect, cornerRadius: w * 0.45),
                         with: .color(Palette.skyDeep))
        }
    }

    private func drawScarf(_ context: inout GraphicsContext, _ mira: MiraGeometry) {
        context.fill(mira.band(from: 0.34, to: 0.66, outer: 1.04, inner: 0.84),
                     with: .color(Palette.cheek))

        // A tail hanging off one side of the wrap.
        let hang = mira.onRim(0.375, 0.96)
        let w: CGFloat = mira.radius * 0.13
        let h: CGFloat = mira.radius * 0.34
        let rect = CGRect(x: hang.x - w / 2, y: hang.y, width: w, height: h)
        context.fill(Path(roundedRect: rect, cornerRadius: w * 0.45),
                     with: .color(Palette.cheek))
    }

    /// Four-pointed sparkles orbiting her, each on its own beat so they never
    /// twinkle together.
    private func drawSparkles(_ context: inout GraphicsContext, _ mira: MiraGeometry) {
        let places: [(turn: Double, scale: CGFloat, beat: Double)] = [
            (-0.10, 0.16, 0.0), (0.14, 0.12, 1.9), (-0.30, 0.11, 3.4), (0.33, 0.14, 5.1)
        ]
        for place in places {
            let pulse: Double = (sin(mira.t * 1.8 + place.beat) + 1) / 2
            let size: CGFloat = mira.radius * place.scale * CGFloat(0.55 + pulse * 0.45)
            let at = mira.onRim(place.turn, 1.24)
            let rect = CGRect(x: at.x - size / 2, y: at.y - size / 2,
                              width: size, height: size)
            context.fill(Sparkle().path(in: rect),
                         with: .color(Palette.amber.opacity(0.45 + pulse * 0.55)))
        }
    }
}
