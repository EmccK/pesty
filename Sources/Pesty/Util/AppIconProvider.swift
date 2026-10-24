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

    // MARK: - Warming

    private static var warmQueue: [String] = []
    private static var isWarming = false

    /// Samples the colors for `bundleIDs` one per main-queue turn.
    ///
    /// Sampling one icon costs ~3 ms — the icon has to be rasterized before its
    /// pixels can vote — so doing it for every card of the first presentation
    /// stalls the bar as it slides up. Walking the list a turn at a time keeps
    /// any single frame to a few milliseconds, and the hotkey usually arrives
    /// long after the queue has drained.
    static func warmCache(for bundleIDs: [String]) {
        let queued = Set(warmQueue)
        for bundleID in Set(bundleIDs) where colorCache[bundleID] == nil && !queued.contains(bundleID) {
            warmQueue.append(bundleID)
        }
        guard !isWarming, !warmQueue.isEmpty else { return }
        isWarming = true
        stepWarmQueue()
    }

    private static func stepWarmQueue() {
        guard !warmQueue.isEmpty else {
            isWarming = false
            return
        }
        _ = dominantColor(forBundleID: warmQueue.removeFirst())
        DispatchQueue.main.async { stepWarmQueue() }
    }

    /// Downsamples the icon and picks its characteristic color.
    ///
    /// A hue histogram weighted by saturation finds a brand color; icons that
    /// are genuinely monochrome (a black logo on white, say) have no saturated
    /// pixels to vote with, so those fall back to the mean of their dark pixels
    /// — which is what makes a black-and-white app's card band read black.
    ///
    /// The loop reads raw sRGB bytes and does the HSB arithmetic itself. An
    /// `NSColor` per pixel — the obvious version — cost ~6 ms per icon, and the
    /// bar pays this for every source app the first time it is shown, on the
    /// main thread, mid-animation.
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
        var hueBest = [HueSample?](repeating: nil, count: 24)
        var darkSum = (r: 0.0, g: 0.0, b: 0.0, weight: 0.0)

        for index in stride(from: 0, to: side * side * 4, by: 4) {
            let alpha = Double(data[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = Double(data[index]) / 255
            let g = Double(data[index + 1]) / 255
            let b = Double(data[index + 2]) / 255
            let pixel = hsb(r, g, b)

            if pixel.saturation > 0.30, pixel.brightness > 0.18 {
                let bucket = min(23, Int(pixel.hue * 24))
                let score = pixel.saturation * pixel.brightness
                hueWeights[bucket] += score
                if hueBest[bucket] == nil || hueBest[bucket]!.score < score {
                    hueBest[bucket] = HueSample(hue: pixel.hue,
                                                saturation: pixel.saturation,
                                                brightness: pixel.brightness,
                                                score: score)
                }
            } else if pixel.brightness < 0.35 {
                darkSum.r += r
                darkSum.g += g
                darkSum.b += b
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
            return tempered(hue: best.hue,
                            saturation: best.saturation,
                            brightness: best.brightness)
        }

        if darkSum.weight > pixelCount * 0.10 {
            let mean = hsb(darkSum.r / darkSum.weight,
                           darkSum.g / darkSum.weight,
                           darkSum.b / darkSum.weight)
            return tempered(hue: mean.hue,
                            saturation: mean.saturation,
                            brightness: mean.brightness)
        }
        return nil
    }

    private struct HueSample {
        let hue: Double
        let saturation: Double
        let brightness: Double
        let score: Double
    }

    /// Hue in `0..<1`, saturation and brightness in `0...1`, straight from the
    /// sRGB components — the same values `NSColor.getHue` would report, without
    /// the object.
    private static func hsb(_ r: Double, _ g: Double, _ b: Double)
        -> (hue: Double, saturation: Double, brightness: Double) {
        let high = max(r, g, b)
        let low = min(r, g, b)
        let delta = high - low
        let brightness = high
        guard delta > 0, high > 0 else { return (0, 0, brightness) }
        let saturation = delta / high
        var hue: Double
        if high == r {
            hue = (g - b) / delta
        } else if high == g {
            hue = 2 + (b - r) / delta
        } else {
            hue = 4 + (r - g) / delta
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, saturation, brightness)
    }

    /// Keeps a band vivid enough to read as the app's own color while staying
    /// dark enough for white text: Paste's bands sit between roughly 0.35 and
    /// 0.95 brightness at 0.45 saturation or better.
    private static func tempered(hue: Double,
                                 saturation: Double,
                                 brightness: Double) -> NSColor? {
        let clampedSaturation = min(max(saturation, 0.45), 1.0)
        let clampedBrightness = min(max(brightness, 0.32), 0.95)
        return NSColor(hue: CGFloat(hue),
                       saturation: clampedSaturation,
                       brightness: clampedBrightness,
                       alpha: 1).usingColorSpace(.sRGB)
    }

    static let generic: NSImage =
        NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        ?? NSImage()
}
