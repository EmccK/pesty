import AppKit

struct ClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    var type: ClipType
    var text: String?
    var rtfData: Data?
    var htmlData: Data?
    var imageFileName: String?
    var imageHash: String?
    var fileURLs: [String]
    var colorHex: String?

    var sourceBundleID: String?
    var sourceAppName: String?

    var customTitle: String?
    var createdAt: Date

    // MARK: - Derived, cache-only state
    //
    // Everything below is computed once per content change instead of on every
    // render. The strip re-evaluates a card's body for selection, hover, and
    // every scroll-driven size pass, and each of these used to rebuild strings
    // (displayTitle, searchableText, metaLeft, the relative timestamp) or cache
    // dictionaries (pinboard lookups) on every one of those passes.

    // Synthesized stays in the file format (version tolerant, and the
    // explicitly cached values must not leak into `Equatable` comparisons of
    // the persisted content). They are rebuilt on init and on decode.

    /// Lowercased haystack for the bar's search; filtering 5 000 clips used to
    /// rebuild five joined strings per item per keystroke.
    private(set) var searchTextLowercased: String = ""
    /// `displayTitle` as last computed, including the localized fallbacks.
    private(set) var cachedDisplayTitle: String = ""
    /// The band's relative timestamp, resolved at the moment the clip was
    /// recorded. The band shows the clip's age, so recomputing it per render
    /// bought nothing but a `RelativeDateTimeFormatter` allocation.
    private(set) var cachedRelativeDate: String = ""

    init(id: UUID = UUID(),
         type: ClipType,
         text: String? = nil,
         rtfData: Data? = nil,
         htmlData: Data? = nil,
         imageFileName: String? = nil,
         imageHash: String? = nil,
         fileURLs: [String] = [],
         colorHex: String? = nil,
         sourceBundleID: String? = nil,
         sourceAppName: String? = nil,
         customTitle: String? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.type = type
        self.text = text
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.imageFileName = imageFileName
        self.imageHash = imageHash
        self.fileURLs = fileURLs
        self.colorHex = colorHex
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.customTitle = customTitle
        self.createdAt = createdAt
        refreshDerivedState()
    }

    var charCount: Int { text?.count ?? 0 }

    /// Recomputes the cache-only fields. Call after mutating anything they read.
    ///
    /// `createdAt` is stamped in so a promoted clip (same content, new copy
    /// time) also refreshes its band timestamp. `nonisolated` because decoding
    /// runs off the main actor.
    nonisolated mutating func refreshDerivedState(now: Date = Date()) {
        searchTextLowercased = Self.searchHaystack(for: self)
        cachedDisplayTitle = computeDisplayTitle()
        cachedRelativeDate = Self.relativeDate(for: createdAt, now: now)
    }

    private nonisolated static func searchHaystack(for item: ClipItem) -> String {
        var parts: [String] = []
        if let customTitle = item.customTitle { parts.append(customTitle) }
        if let text = item.text { parts.append(text) }
        if let sourceAppName = item.sourceAppName { parts.append(sourceAppName) }
        if !item.fileURLs.isEmpty { parts.append(item.fileURLs.joined(separator: " ")) }
        if let colorHex = item.colorHex { parts.append(colorHex) }
        return parts.joined(separator: " ").lowercased()
    }

    /// "Just now" for the first seconds, then the system's relative wording.
    /// Locale comes from the app's own language setting, not the process.
    static func relativeDate(for date: Date, now: Date = Date()) -> String {
        let secs = now.timeIntervalSince(date)
        if secs < 8 { return L("Just now") }
        return ClipRelativeDateFormatter.relativeString(for: date, now: now)
    }

    var plainText: String? {
        switch type {
        case .image:
            return nil
        case .color:
            return colorHex
        case .file:
            let paths = fileURLs.map { URL(string: $0)?.path ?? $0 }
            return paths.isEmpty ? nil : paths.joined(separator: "\n")
        case .text, .richText, .link:
            return text
        }
    }

    var displayTitle: String { cachedDisplayTitle }

    private nonisolated func computeDisplayTitle() -> String {
        if let t = customTitle, !t.isEmpty { return t }
        switch type {
        case .link:
            if let t = text, let url = URL(string: t.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return url.host ?? t
            }
            return text ?? L("Link")
        case .image:
            return L("Image")
        case .file:
            return fileURLs.first.flatMap { URL(string: $0)?.lastPathComponent } ?? L("File")
        case .color:
            return colorHex ?? L("Color")
        default:
            let firstLine = (text ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return firstLine.isEmpty ? type.label : String(firstLine.prefix(60))
        }
    }

    /// Kept for callers outside the filter; the strip reads the cached field.
    var searchableText: String { searchTextLowercased }

    func sameContent(as other: ClipItem) -> Bool {
        guard type == other.type else { return false }
        switch type {
        case .image:
            if let h = imageHash, let oh = other.imageHash { return h == oh }
            return imageFileName == other.imageFileName
        case .color:
            return colorHex == other.colorHex
        case .file:
            return fileURLs == other.fileURLs
        default:
            return text == other.text
        }
    }
}

/// One formatter for every card band. `RelativeDateTimeFormatter` is not cheap
/// to build (and is rate-limited in its relative strings), so the strip used to
/// pay for a fresh one per visible card per render.
enum ClipRelativeDateFormatter {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func relativeString(for date: Date, now: Date) -> String {
        let locale = Localization.shared.locale
        return MainActor.assumeIsolated {
            if formatter.locale != locale { formatter.locale = locale }
            return formatter.localizedString(for: date, relativeTo: now)
        }
    }
}
