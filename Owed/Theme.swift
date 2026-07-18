import SwiftUI
import UIKit

/// Owed design tokens — engraved banknote / court docket language.
/// Mirrors lib/theme.js from the Expo scaffold.
enum T {
    static let ink       = Color(hex: 0x12261E)
    static let paper     = Color(hex: 0xFAF8F2)
    static let card      = Color.white
    static let green     = Color(hex: 0x1E5B45)
    static let greenSoft = Color(hex: 0xE4EEE8)
    static let gold      = Color(hex: 0xB98A2F)
    static let goldSoft  = Color(hex: 0xF4EBD8)
    static let stamp     = Color(hex: 0xA63B2A)
    static let stampSoft = Color(hex: 0xF6E5E1)
    static let line      = Color(hex: 0xE2DDD0)
    static let mut       = Color(hex: 0x5E6B62)
    static let ctaOff    = Color(hex: 0xB9C6BF)
    static let tagProofBg = Color(hex: 0xEEF0F4)
    static let tagProofFg = Color(hex: 0x4A5568)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Brand typography with graceful degradation and Dynamic Type.
///
/// If the OFL-licensed TTFs are present in Owed/Fonts (see Scripts/fetch-fonts.sh),
/// we get the full engraved-banknote face: Fraunces for amounts, Public Sans for
/// body, IBM Plex Mono for case numbers. If not, we fall back to the closest
/// system designs (New York serif, SF, SF Mono) so the app is always shippable.
///
/// Both paths track the user's text size: custom faces via
/// `Font.custom(_:size:relativeTo:)`, system fallbacks via `UIFontMetrics`.
/// Prefer `OwedFont.icon` for SF Symbols next to copy so icons scale too.
enum OwedFont {
    private static func has(_ name: String) -> Bool {
        UIFont(name: name, size: 12) != nil
    }

    // Cached once — font registration doesn't change mid-session.
    private static let fraunces      = has("Fraunces-SemiBold")
    private static let frauncesBold  = has("Fraunces-Bold")
    private static let publicSans    = has("PublicSans-Regular")
    private static let plexMono      = has("IBMPlexMono-Medium")

    private static func scaled(_ size: CGFloat, style: UIFont.TextStyle) -> CGFloat {
        UIFontMetrics(forTextStyle: style).scaledValue(for: size)
    }

    /// Amounts and headlines (Fraunces 650 in the RN scaffold).
    static func display(_ size: CGFloat) -> Font {
        fraunces
            ? .custom("Fraunces-SemiBold", size: size, relativeTo: .title2)
            : .system(size: scaled(size, style: .title2), weight: .semibold, design: .serif)
    }

    /// Heavier display cut (Fraunces 750).
    static func displayBold(_ size: CGFloat) -> Font {
        frauncesBold
            ? .custom("Fraunces-Bold", size: size, relativeTo: .title)
            : .system(size: scaled(size, style: .title1), weight: .bold, design: .serif)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard publicSans else {
            return .system(size: scaled(size, style: .body), weight: weight)
        }
        switch weight {
        case .bold:     return .custom("PublicSans-Bold", size: size, relativeTo: .body)
        case .semibold: return .custom("PublicSans-SemiBold", size: size, relativeTo: .body)
        default:        return .custom("PublicSans-Regular", size: size, relativeTo: .body)
        }
    }

    /// Case numbers and docket stamps.
    static func mono(_ size: CGFloat) -> Font {
        plexMono
            ? .custom("IBMPlexMono-Medium", size: size, relativeTo: .caption)
            : .system(size: scaled(size, style: .caption1), weight: .medium, design: .monospaced)
    }

    /// SF Symbols next to Dynamic Type text — `.system(size:)` alone
    /// ignores the user's text size and makes icons look stranded at
    /// accessibility sizes.
    static func icon(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: scaled(size, style: .body), weight: weight)
    }
}

// MARK: - Shared chrome

/// The docket-card surface used across the app.
struct DocketSurface: ViewModifier {
    var cornerRadius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .background(T.card)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(T.line, lineWidth: 1)
            )
    }
}

extension View {
    func docketSurface(cornerRadius: CGFloat = 16) -> some View {
        modifier(DocketSurface(cornerRadius: cornerRadius))
    }
}
