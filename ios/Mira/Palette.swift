import SwiftUI

/// Four given colours, plus the shades needed to make them work as an
/// interface:
///
///   #FFF9D2  butter    #FFEBCC  peach
///   #BFDDF0  powder    #8CC0EB  sky
///
/// Warm cream carries the ground, blue carries anything you can act on.
/// `skyDeep` and `amber` are darkened from `sky` and `peach` — white text on
/// #8CC0EB is about 1.9:1, nowhere near legible, so the button blue has to be
/// a shade of it rather than the tint itself.
enum Palette {

    // The palette as given
    static let butter = Color(red: 1.00, green: 0.976, blue: 0.824)  // #FFF9D2
    static let peach  = Color(red: 1.00, green: 0.922, blue: 0.800)  // #FFEBCC
    static let powder = Color(red: 0.749, green: 0.867, blue: 0.941) // #BFDDF0
    static let sky    = Color(red: 0.549, green: 0.753, blue: 0.922) // #8CC0EB

    // Derived
    static let skyDeep = Color(red: 0.204, green: 0.478, blue: 0.706) // #347AB4
    static let skyInk  = Color(red: 0.145, green: 0.365, blue: 0.553) // #255D8D
    static let amber   = Color(red: 0.898, green: 0.639, blue: 0.353) // #E5A35A
    static let butterDeep = Color(red: 1.00, green: 0.949, blue: 0.729) // #FFF2BA

    static var background: LinearGradient {
        LinearGradient(colors: [butter, peach], startPoint: .top, endPoint: .bottom)
    }

    // Ink — deep slate blue, so text belongs to the blues rather than to grey
    static let ink      = Color(red: 0.169, green: 0.231, blue: 0.290) // #2B3B4A
    static let inkSoft  = Color(red: 0.369, green: 0.443, blue: 0.514) // #5E7183
    static let inkFaint = Color(red: 0.608, green: 0.682, blue: 0.741) // #9BAEBD

    static let card  = Color.white
    static let alert = Color(red: 0.804, green: 0.404, blue: 0.239)   // #CD673D

    // Face
    static let eye   = Color(red: 0.145, green: 0.204, blue: 0.263)   // #253443
    static let cheek = Color(red: 1.00, green: 0.784, blue: 0.627)    // #FFC8A0

    /// A blue-grey shadow. A neutral one greys the cream out.
    static let shadow     = Color(red: 0.29, green: 0.42, blue: 0.53).opacity(0.20)
    static let shadowSoft = Color(red: 0.29, green: 0.42, blue: 0.53).opacity(0.11)
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
