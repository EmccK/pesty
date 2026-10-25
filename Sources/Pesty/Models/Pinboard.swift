import SwiftUI

struct Pinboard: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String

    init(id: UUID = UUID(), name: String, colorHex: String = "#5B8DEF") {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }

    var color: Color { Color(hex: colorHex) ?? .accentColor }
}

// MARK: - Colors

extension Pinboard {
    /// The colors a board can take, in the order Paste lists them under its
    /// own context menu: the eight system hues, at full strength, because a
    /// board's color is the one thing that has to survive being read at a
    /// glance across a row of cards.
    ///
    /// They are hard-coded rather than read from `NSColor.systemRed` & co. so
    /// that a board keeps the color it was given: the system values shift
    /// between macOS releases, and a board's color is persisted in its record.
    static let palette: [String] = [
        "#FF3B30",  // red
        "#FF9500",  // orange
        "#FFCC00",  // yellow
        "#34C759",  // green
        "#007AFF",  // blue
        "#AF52DE",  // purple
        "#FF2D55",  // pink
        "#8E8E93",  // gray
    ]

    /// A board the user did not pick a color for gets one at random: every
    /// board starting out the same blue made the tab row read as a single
    /// control rather than a row of separate boards.
    static var randomColorHex: String {
        palette.randomElement() ?? "#007AFF"
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        case 8:
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        default:
            return nil
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
