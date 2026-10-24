import AppKit

@MainActor
enum AppIconProvider {
    private static var cache: [String: NSImage] = [:]
    private static var colorCache: [String: NSColor] = [:]

    static func icon(forBundleID bundleID: String?) -> NSImage {
        guard let bundleID else { return generic }
        if let cached = cache[bundleID] { return cached }
        var image = generic
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        cache[bundleID] = image
        return image
    }

    /// The color a card's header band takes for this source app.
    ///
    /// Paste tints each card's header with the dominant color of the app that
    /// produced the clip, so the strip reads as a row of colored cards. The
    /// color is sampled from the icon's own artwork: the most common hue among
    /// its saturated pixels, which is the brand color rather than the white or
    /// transparent padding most macOS icons carry.
    static func dominantColor(forBundleID bundleID: String?) -> NSColor {
        guard let bundleID else { return neutral }
        if let cached = colorCache[bundleID] { return cached }
        let color = sample(from: icon(forBundleID: bundleID)) ?? neutral
        colorCache[bundleID] = color
        return color
    }

    /// Fallback for clips with no source app (and for icons without a hue):
    /// a muted slate that sits behind white text in both appearances.
    static let neutral = NSColor(srgbRed: 0.35, green: 0.36, blue: 0.40, alpha: 1)

    /// Downsamples the icon and picks its characteristic color.
    ///
    /// A hue histogram weighted by saturation finds a brand color; icons that
    /// are genuinely monochrome (a black logo on white, say) have no saturated
    /// pixels to vote with, so those fall back to the mean of their dark pixels
    /// — which is what makes a black-and-white app's card band read black.
    private static func sample(from image: NSImage) -> NSColor? {
        let side = 32
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: side * 4,
            bitsPerPixel: 32
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                   from: .zero,
                   operation: .copy,
                   fraction: 1)

        guard let data = rep.bitmapData else { return nil }

        var hueWeights = [Double](repeating: 0, count: 24)
        // The band is a vivid brand color, not the average of the icon: keep the
        // most saturated pixel of each hue bucket instead of blending, so a logo
        // with a bright accent on a muted field still reads as that accent.
        var hueBest = [(color: NSColor, score: Double)?](repeating: nil, count: 24)
        var darkSum = (r: 0.0, g: 0.0, b: 0.0, weight: 0.0)

        for index in stride(from: 0, to: side * side * 4, by: 4) {
            let alpha = Double(data[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            let color = NSColor(
                srgbRed: CGFloat(data[index]) / 255,
                green: CGFloat(data[index + 1]) / 255,
                blue: CGFloat(data[index + 2]) / 255,
                alpha: 1
            )
            guard let hsb = color.usingColorSpace(.sRGB) else { continue }
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
            hsb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)

            if saturation > 0.30, brightness > 0.18 {
                let bucket = min(23, Int(hue * 24))
                let score = Double(saturation) * Double(brightness)
                hueWeights[bucket] += score
                if hueBest[bucket] == nil || hueBest[bucket]!.score < score {
                    hueBest[bucket] = (color, score)
                }
            } else if brightness < 0.35 {
                darkSum.r += Double(hsb.redComponent)
                darkSum.g += Double(hsb.greenComponent)
                darkSum.b += Double(hsb.blueComponent)
                darkSum.weight += 1
            }
        }

        let totalHue = hueWeights.reduce(0, +)
        let pixelCount = Double(side * side)
        if totalHue > pixelCount * 0.02 {
            // Smooth across neighbouring buckets so a logo split between two
            // shades does not pick the boundary.
            let smoothed = (0..<24).map { index in
                hueWeights[(index + 23) % 24] * 0.25
                    + hueWeights[index]
                    + hueWeights[(index + 1) % 24] * 0.25
            }
            guard let peak = smoothed.indices.max(by: { smoothed[$0] < smoothed[$1] }),
                  let best = hueBest[peak] else { return nil }
            return tempered(best.color)
        }

        if darkSum.weight > pixelCount * 0.10 {
            let raw = NSColor(
                srgbRed: CGFloat(darkSum.r / darkSum.weight),
                green: CGFloat(darkSum.g / darkSum.weight),
                blue: CGFloat(darkSum.b / darkSum.weight),
                alpha: 1
            )
            return tempered(raw)
        }
        return nil
    }

    /// Keeps a band vivid enough to read as the app's own color while staying
    /// dark enough for white text: Paste's bands sit between roughly 0.35 and
    /// 0.95 brightness at 0.45 saturation or better.
    private static func tempered(_ color: NSColor) -> NSColor? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        let clampedSaturation = min(max(saturation, 0.45), 1.0)
        let clampedBrightness = min(max(brightness, 0.32), 0.95)
        return NSColor(hue: hue,
                       saturation: clampedSaturation,
                       brightness: clampedBrightness,
                       alpha: 1).usingColorSpace(.sRGB)
    }

    static let generic: NSImage =
        NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        ?? NSImage()
}
