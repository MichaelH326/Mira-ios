import SwiftUI

/// Strawberry yogurt: a pale pink ground, hot pink for anything live, and
/// pastels for the states in between. One place so a colour never gets
/// invented halfway down a view.
enum Palette {

    // Ground
    static let cream   = Color(red: 1.00, green: 0.97, blue: 0.98)   // #FFF7FA
    static let yogurt  = Color(red: 0.99, green: 0.89, blue: 0.92)   // #FDE3EB
    static let blush   = Color(red: 1.00, green: 0.93, blue: 0.95)   // #FFEDF2

    /// The gradient behind every screen.
    static var background: LinearGradient {
        LinearGradient(colors: [cream, yogurt], startPoint: .top, endPoint: .bottom)
    }

    // Accents
    static let hotPink = Color(red: 1.00, green: 0.18, blue: 0.53)   // #FF2E87
    static let deepRose = Color(red: 0.85, green: 0.12, blue: 0.44)  // #D91F70
    static let sherbet = Color(red: 1.00, green: 0.72, blue: 0.80)   // #FFB8CC
    static let lilac   = Color(red: 0.85, green: 0.80, blue: 0.98)   // #D9CCFA
    static let mint    = Color(red: 0.71, green: 0.93, blue: 0.85)   // #B5EDD9

    // Ink — plum rather than grey, so text sits in the same family as the ground
    static let ink      = Color(red: 0.34, green: 0.11, blue: 0.22)  // #571C38
    static let inkSoft  = Color(red: 0.55, green: 0.33, blue: 0.43)  // #8C546E
    static let inkFaint = Color(red: 0.72, green: 0.55, blue: 0.63)  // #B78CA1

    static let card  = Color.white
    static let alert = Color(red: 0.80, green: 0.24, blue: 0.20)     // #CC3D33

    /// Soft pink shadow — a grey one turns the pastels muddy.
    static let shadow = Color(red: 0.85, green: 0.45, blue: 0.60).opacity(0.22)
}
