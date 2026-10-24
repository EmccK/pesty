import SwiftUI

enum Theme {
    /// Cards are square: Paste's strip measures 252 × 252 pt at a 337 pt bar,
    /// so the side follows the space the strip has rather than a fixed width.
    static let cardMinSide: CGFloat = 150
    static let cardMaxSide: CGFloat = 320
    static let cardSpacing: CGFloat = 21
    /// Corner radius of the bar surface itself. Measured off Paste's own
    /// panel: 24 pt, visibly rounder than the previous 16.
    static let cornerRadius: CGFloat = 24
    /// Paste's card corners measure 14 pt off the colored header band.
    static let cardCorner: CGFloat = 14
    static let fileIconSize: CGFloat = 64

    // Paste-style anatomy: a colored header band carrying the type, the
    // timestamp, and the source app icon; the preview fills everything below
    // it; the metadata sits centered along the bottom edge.
    static let cardOverlayInset: CGFloat = 12
    /// Header band height as a fraction of the card side (52 pt on a 252 pt
    /// card in Paste's own strip).
    static let bandHeightRatio: CGFloat = 0.21
    static let bandMinHeight: CGFloat = 38
    static let cardContentTopInset: CGFloat = 10
    static let cardContentBottomInset: CGFloat = 28
    /// Chrome rows of the bar itself, used to work out how much room the strip
    /// has for its square cards. Measured off Paste's own bar: the pill row
    /// sits 48 pt tall and the cards start 60 pt down.
    static let topBarHeight: CGFloat = 48
    static let stripTopPadding: CGFloat = 12
    /// Measured off Paste: cards rest ~27 pt above the panel's bottom edge.
    static let stripBottomPadding: CGFloat = 27

    // MARK: - Adaptive palette
    //
    // Every surface tracks the system appearance: dark mode keeps the HUD
    // look, light mode flips the strip and the cards to light surfaces with
    // dark text. The colors are NSColor dynamic providers so the swap happens
    // inside AppKit whenever a window's effective appearance changes.
    //
    // Card surfaces stay opaque on purpose: the bar floats over the desktop on
    // adaptive glass, and a translucent card would let a light desktop shine
    // through and wash the text out.

    private static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        })
    }

    /// Tint laid over the vibrancy material: frosted white in light mode,
    /// a whisper of white over the dark HUD material in dark mode.
    static let panelTint = dynamic(dark: NSColor.white.withAlphaComponent(0.10),
                                   light: NSColor.white.withAlphaComponent(0.22))

    /// Tint handed to the macOS 26 `NSGlassEffectView`.
    ///
    /// Paste's light glass carries no tint. Dividing the old 12 % black tint
    /// back out of Pesty's measured light panel lands exactly on Paste's
    /// rgb(255, 157, 255) over the purple wallpaper, and Paste's panel follows
    /// light backdrops (rgb(246, 243, 246) over white) the same way clear
    /// glass does. Dark mode keeps the tint so the calibrated dark wash in
    /// `panelWash` below still composites over the same base.
    static let panelGlassTint = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? NSColor.black.withAlphaComponent(0.12) : .clear
    }

    /// Wash drawn over the macOS 26 glass panel.
    ///
    /// Glass alone leaves the bar far too transparent: over a black backdrop it
    /// renders rgb(41) where Paste renders rgb(58), and it keeps climbing with
    /// the backdrop instead of flattening out. Measured against calibrated
    /// backdrops, Paste's dark bar fits `panel = 0.043 × backdrop + 58`, so this
    /// wash pins a near-flat mid-gray on the same curve. In light mode the
    /// clear-tinted glass already matches Paste on both calibration backdrops —
    /// rgb(255, 157, 255) over the purple wallpaper and rgb(246, 243, 246) over
    /// a light one — so the light wash stays clear and keeps the panel
    /// translucent the way Paste's is.
    static let panelWash = dynamic(dark: NSColor(white: 0.275, alpha: 0.82),
                                   light: .clear)

    /// The card body under the band. Paste's banded cards sit on plain white in
    /// light mode (its older floating-header cards used 245), so the content
    /// area and the band meet at a hard edge.
    static let cardBody = dynamic(dark: NSColor(srgbRed: 0.129, green: 0.129, blue: 0.141, alpha: 1),
                                  light: NSColor(white: 1.0, alpha: 1))
    /// Paste's selection ring is the system accent blue; sampling its ring and
    /// converting to sRGB lands exactly on rgb(0, 122, 255).
    static let selection = Color(red: 0, green: 0.478, blue: 1)
    /// Paste's ring is a 4 pt capsule behind the card, not a wide halo.
    static let selectedCardRing: CGFloat = 4
    // Paste aligns its first card with the toolbar content: both sit 18 pt
    // off the panel edge, with the selected-card ring extra so a selected
    // edge card never clips against the ScrollView boundary.
    static let cardStripHorizontalPadding: CGFloat = selectedCardRing + 14

    static let chromeTextPrimary = dynamic(dark: NSColor.white.withAlphaComponent(0.95),
                                           light: NSColor.black.withAlphaComponent(0.85))
    static let chromeTextSecondary = dynamic(dark: NSColor.white.withAlphaComponent(0.55),
                                             light: NSColor.black.withAlphaComponent(0.50))
    static let chromeTextTertiary = dynamic(dark: NSColor.white.withAlphaComponent(0.34),
                                            light: NSColor.black.withAlphaComponent(0.30))

    static let cardTextPrimary = dynamic(dark: NSColor.white.withAlphaComponent(0.92),
                                         light: NSColor.black.withAlphaComponent(0.82))
    static let cardTextSecondary = dynamic(dark: NSColor.white.withAlphaComponent(0.58),
                                           light: NSColor.black.withAlphaComponent(0.50))
    static let cardTextTertiary = dynamic(dark: NSColor.white.withAlphaComponent(0.38),
                                          light: NSColor.black.withAlphaComponent(0.32))

    /// Text on the colored header band. Paste keeps it plain white at two
    /// strengths and relies on the band being dark enough, which the dominant
    /// color clamp in `AppIconProvider` guarantees.
    static let bandTextPrimary = Color.white
    static let bandTextSecondary = Color.white.opacity(0.72)

    static let headerText = dynamic(dark: NSColor.white,
                                    light: NSColor.black.withAlphaComponent(0.85))
    static let headerSubText = dynamic(dark: NSColor.white.withAlphaComponent(0.72),
                                       light: NSColor.black.withAlphaComponent(0.50))

    /// Gradient base under the floating chrome: dark over bright screenshots in
    /// dark mode, a frosted white in light mode.
    static let scrimBase = dynamic(dark: NSColor.black, light: NSColor.white)
    /// Text shadow that keeps the floating chrome readable over the scrim.
    static let overlayTextShadow = dynamic(dark: NSColor.black.withAlphaComponent(0.45),
                                           light: NSColor.white.withAlphaComponent(0.65))

    /// Transparency checkerboard behind image clips, per appearance.
    static let checkerBase = dynamic(dark: NSColor(white: 0.0667, alpha: 1),
                                     light: NSColor.white)
    static let checkerAlt = dynamic(dark: NSColor(white: 0.0941, alpha: 1),
                                    light: NSColor(white: 0.87, alpha: 1))

    static let fieldBG = dynamic(dark: NSColor.white.withAlphaComponent(0.09),
                                 light: NSColor.black.withAlphaComponent(0.06))
    static let pillBG = dynamic(dark: NSColor.white.withAlphaComponent(0.13),
                                light: NSColor.black.withAlphaComponent(0.075))
    static let pillSelected = dynamic(dark: NSColor.white.withAlphaComponent(0.22),
                                      light: NSColor.black.withAlphaComponent(0.12))
}

extension Date {
    var clipRelative: String {
        let secs = -timeIntervalSinceNow
        switch secs {
        case ..<5:        return L("Now")
        case ..<60:       return "\(Int(secs))s"
        case ..<3600:     return "\(Int(secs / 60))m"
        case ..<86_400:   return "\(Int(secs / 3600))h"
        case ..<604_800:  return "\(Int(secs / 86_400))d"
        default:
            return ClipDateFormatters.shortDayString(for: self)
        }
    }

    /// Shares one formatter with `ClipItem`: a card band asks for this on every
    /// render pass, and building a `RelativeDateTimeFormatter` each time shows
    /// up as a stutter the moment the strip starts scrolling.
    var clipRelativeLong: String {
        let secs = -timeIntervalSinceNow
        if secs < 8 { return L("Just now") }
        return ClipRelativeDateFormatter.relativeString(for: self, now: Date())
    }
}

/// Formatters the strip reaches for on every render. Both are expensive to
/// build and cheap to reuse, so they are created once per locale and then only
/// read.
enum ClipDateFormatters {
    private final class Box: @unchecked Sendable {
        var formatter: DateFormatter?
        var locale: Locale?
    }
    private static let box = Box()
    private static let lock = NSLock()

    static func shortDayString(for date: Date) -> String {
        let locale = Localization.shared.locale
        lock.lock()
        defer { lock.unlock() }
        if box.formatter == nil || box.locale != locale {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = DateFormatter.dateFormat(
                fromTemplate: "MMMd", options: 0, locale: locale) ?? "MMM d"
            box.formatter = formatter
            box.locale = locale
        }
        return box.formatter!.string(from: date)
    }
}
