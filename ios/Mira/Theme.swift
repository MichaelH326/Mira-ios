import SwiftUI

/// A colour scheme the user picks during onboarding.
///
/// Every theme is the same five roles, so nothing downstream knows which one
/// is active: two grounds, a soft mid tone, an accent that anything touchable
/// is drawn in, and a warm counterpoint.
enum Theme: String, CaseIterable, Identifiable {
    case butter, blossom, matcha, lilac, dusk

    var id: String { rawValue }

    var name: String {
        switch self {
        case .butter:  return "Butter & Sky"
        case .blossom: return "Blossom"
        case .matcha:  return "Matcha"
        case .lilac:   return "Lilac"
        case .dusk:    return "Dusk"
        }
    }

    /// Top of the background gradient.
    var groundTop: Color {
        switch self {
        case .butter:  return Color(red: 1.00, green: 0.976, blue: 0.824)
        case .blossom: return Color(red: 1.00, green: 0.961, blue: 0.973)
        case .matcha:  return Color(red: 0.980, green: 0.996, blue: 0.925)
        case .lilac:   return Color(red: 0.980, green: 0.969, blue: 1.00)
        case .dusk:    return Color(red: 0.949, green: 0.961, blue: 1.00)
        }
    }

    /// Bottom of the background gradient.
    var groundBottom: Color {
        switch self {
        case .butter:  return Color(red: 1.00, green: 0.922, blue: 0.800)
        case .blossom: return Color(red: 1.00, green: 0.886, blue: 0.925)
        case .matcha:  return Color(red: 0.910, green: 0.969, blue: 0.898)
        case .lilac:   return Color(red: 0.925, green: 0.902, blue: 0.988)
        case .dusk:    return Color(red: 0.878, green: 0.902, blue: 0.980)
        }
    }

    /// Soft mid tone: chips, badges, dividers.
    var soft: Color {
        switch self {
        case .butter:  return Color(red: 0.749, green: 0.867, blue: 0.941)
        case .blossom: return Color(red: 1.00, green: 0.780, blue: 0.855)
        case .matcha:  return Color(red: 0.792, green: 0.906, blue: 0.780)
        case .lilac:   return Color(red: 0.851, green: 0.812, blue: 0.976)
        case .dusk:    return Color(red: 0.749, green: 0.800, blue: 0.929)
        }
    }

    /// The accent. Anything you can act on is this colour.
    var accent: Color {
        switch self {
        case .butter:  return Color(red: 0.549, green: 0.753, blue: 0.922)
        case .blossom: return Color(red: 1.00, green: 0.482, blue: 0.663)
        case .matcha:  return Color(red: 0.494, green: 0.749, blue: 0.510)
        case .lilac:   return Color(red: 0.663, green: 0.573, blue: 0.937)
        case .dusk:    return Color(red: 0.451, green: 0.545, blue: 0.847)
        }
    }

    /// A darker accent. White text needs this — the tints are far too light
    /// to carry it, most of them under 2:1.
    var accentDeep: Color {
        switch self {
        case .butter:  return Color(red: 0.204, green: 0.478, blue: 0.706)
        case .blossom: return Color(red: 0.812, green: 0.204, blue: 0.443)
        case .matcha:  return Color(red: 0.216, green: 0.510, blue: 0.278)
        case .lilac:   return Color(red: 0.400, green: 0.290, blue: 0.729)
        case .dusk:    return Color(red: 0.212, green: 0.298, blue: 0.612)
        }
    }

    /// Darker again, for accent-coloured text on a pale ground.
    var accentInk: Color {
        switch self {
        case .butter:  return Color(red: 0.145, green: 0.365, blue: 0.553)
        case .blossom: return Color(red: 0.612, green: 0.129, blue: 0.325)
        case .matcha:  return Color(red: 0.145, green: 0.376, blue: 0.196)
        case .lilac:   return Color(red: 0.302, green: 0.204, blue: 0.573)
        case .dusk:    return Color(red: 0.149, green: 0.216, blue: 0.459)
        }
    }

    /// Warm counterpoint: sparkles, the mouth, "thinking".
    var warm: Color {
        switch self {
        case .butter:  return Color(red: 0.898, green: 0.639, blue: 0.353)
        case .blossom: return Color(red: 0.949, green: 0.545, blue: 0.478)
        case .matcha:  return Color(red: 0.902, green: 0.686, blue: 0.325)
        case .lilac:   return Color(red: 0.933, green: 0.600, blue: 0.541)
        case .dusk:    return Color(red: 0.918, green: 0.643, blue: 0.400)
        }
    }

    /// Text. Tinted toward the accent's family so type belongs to the scheme
    /// rather than sitting on it in grey.
    var ink: Color {
        switch self {
        case .butter:  return Color(red: 0.169, green: 0.231, blue: 0.290)
        case .blossom: return Color(red: 0.278, green: 0.129, blue: 0.196)
        case .matcha:  return Color(red: 0.145, green: 0.216, blue: 0.161)
        case .lilac:   return Color(red: 0.200, green: 0.161, blue: 0.290)
        case .dusk:    return Color(red: 0.137, green: 0.176, blue: 0.278)
        }
    }

    var inkSoft: Color { ink.opacity(0.66) }
    var inkFaint: Color { ink.opacity(0.40) }

    /// The theme in use. Read at draw time so a change in Settings applies
    /// everywhere at once without every view holding a copy.
    static var current: Theme {
        guard let raw = UserDefaults.standard.string(forKey: Prefs.themeKey),
              let theme = Theme(rawValue: raw) else { return .butter }
        return theme
    }
}
