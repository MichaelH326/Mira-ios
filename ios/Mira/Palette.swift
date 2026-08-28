import SwiftUI

/// The active theme's colours under stable names.
///
/// Every value reads `Theme.current` at draw time, so switching themes needs
/// no call-site changes anywhere — a view that re-renders picks up the new
/// scheme. The names are historical (they were the butter-and-sky palette
/// before themes existed) and kept deliberately: they describe the *role*,
/// which is the same in every theme.
enum Palette {

    private static var theme: Theme { Theme.current }

    // Ground
    static var butter: Color { theme.groundTop }
    static var peach: Color { theme.groundBottom }
    static var butterDeep: Color { theme.groundTop.opacity(0.85) }

    static var background: LinearGradient {
        LinearGradient(colors: [theme.groundTop, theme.groundBottom],
                       startPoint: .top, endPoint: .bottom)
    }

    // Accents
    static var powder: Color { theme.soft }
    static var sky: Color { theme.accent }
    static var skyDeep: Color { theme.accentDeep }
    static var skyInk: Color { theme.accentInk }
    static var amber: Color { theme.warm }

    // Ink
    static var ink: Color { theme.ink }
    static var inkSoft: Color { theme.inkSoft }
    static var inkFaint: Color { theme.inkFaint }

    static let card = Color.white
    static let alert = Color(red: 0.804, green: 0.404, blue: 0.239)

    // Mira
    static let eye = Color(red: 0.145, green: 0.184, blue: 0.243)
    static let cheek = Color(red: 1.00, green: 0.612, blue: 0.616)
    /// One pastel hue in three steps — see `Theme.furLight`.
    static var furLight: Color { theme.furLight }
    static var furMid: Color { theme.furMid }
    static var furDeep: Color { theme.furDeep }
    static var hair: Color { theme.furDeep }
    static var hairLight: Color { theme.furMid }

    /// A shadow tinted toward the accent. A neutral one greys the pastels out.
    static var shadow: Color { theme.accentDeep.opacity(0.20) }
    static var shadowSoft: Color { theme.accentDeep.opacity(0.11) }
}

/// A four-pointed anime sparkle.
struct Sparkle: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = rect.midX, cy = rect.midY
        var path = Path()
        path.move(to: CGPoint(x: cx, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: cy),
                          control: CGPoint(x: cx + w * 0.10, y: cy - h * 0.10))
        path.addQuadCurve(to: CGPoint(x: cx, y: rect.maxY),
                          control: CGPoint(x: cx + w * 0.10, y: cy + h * 0.10))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: cy),
                          control: CGPoint(x: cx - w * 0.10, y: cy + h * 0.10))
        path.addQuadCurve(to: CGPoint(x: cx, y: rect.minY),
                          control: CGPoint(x: cx - w * 0.10, y: cy - h * 0.10))
        path.closeSubpath()
        return path
    }
}
