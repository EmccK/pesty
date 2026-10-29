import AppKit

struct ClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    var type: ClipType
    /// Full text while this process still has it. Empty after a spill; the body
    /// is in `textFileName` and the searchable head is `textPrefix`.
    var text: String?
    var textFileName: String?
    var textPrefix: String?
    var textCount: Int = 0
    /// Sidecar in the store's blob directory. Bytes stay out of `store.json`.
    var rtfFileName: String?
    var htmlFileName: String?
    /// Legacy inline payload from an older `store.json`. Spilled to a sidecar
    /// on load, then cleared. Not written back.
    var pendingRTF: Data?
    var pendingHTML: Data?
    var imageFileName: String?
    var imageHash: String?
    var fileURLs: [String]
    var colorHex: String?

    var sourceBundleID: String?
    var sourceAppName: String?

    var customTitle: String?

    /// Which collection this clip is filed under: `nil` is clipboard history,
    /// otherwise the id of the pinboard holding it.
    ///
    /// History and pinboards share one array of clips, the way Paste keeps one
    /// record per copied thing and points it at the clipboard list or a
    /// pinboard. Pinning repoints this field instead of copying the clip, so
    /// "is this pinned?" is readable straight off the clip and the same content
    /// never exists twice on disk.
    var list: UUID?

    /// When the clip was copied. This is the clip's age, which is why history
    /// sorts on it and why a re-copy moves a clip back to the front.
    var createdAt: Date

    /// When the clip was pinned to its board, or `nil` while it sits in
    /// history.
    ///
    /// A board shows its clips newest-pinned first, which is not the order
    /// history keeps them in: re-copying a clip moves it to the front of
    /// history without disturbing where it sits on its board. `createdAt`
    /// cannot answer both questions, so pinning records its own stamp.
    var pinnedAt: Date?

    // MARK: - Derived, cache-only state
    //
    // Everything below is computed once per content change instead of on every
    // render. The strip re-evaluates a card's body for selection, hover, and
    // every scroll-driven size pass, and each of these used to rebuild strings
    // (displayTitle, searchableText, metaLeft, the relative timestamp) or cache
    // dictionaries (pinboard lookups) on every one of those passes.

    // Derived fields stay out of the file and out of `==`. Decode rebuilds them.
    // ponytail: search covers the first 2048 characters and the card shows the
    // first 800. A real index if someone searches the tail of a huge paste.

    private static let searchHaystackLimit = 2_048
    private static let previewTextLimit = 800

    /// Lowercased haystack for the bar's search. Capped so a multi-megabyte
    /// paste does not get a second full copy in memory or in `store.json`.
    private(set) var searchTextLowercased: String = ""
    /// `displayTitle` as last computed, including the localized fallbacks.
    private(set) var cachedDisplayTitle: String = ""
    /// The band's relative timestamp, resolved at the moment the clip was
    /// recorded. The band shows the clip's age, so recomputing it per render
    /// bought nothing but a `RelativeDateTimeFormatter` allocation.
    private(set) var cachedRelativeDate: String = ""
    /// What the card body draws. `lineLimit` still lays out the whole string.
    private(set) var cachedPreviewText: String = ""
    /// Dedup key. Not cryptographic; collisions confirm with `sameContent`.
    private(set) var contentHash: UInt64 = 0

    init(id: UUID = UUID(),
         type: ClipType,
         text: String? = nil,
         rtfFileName: String? = nil,
         htmlFileName: String? = nil,
         pendingRTF: Data? = nil,
         pendingHTML: Data? = nil,
         imageFileName: String? = nil,
         imageHash: String? = nil,
         fileURLs: [String] = [],
         colorHex: String? = nil,
         sourceBundleID: String? = nil,
         sourceAppName: String? = nil,
         customTitle: String? = nil,
         list: UUID? = nil,
         createdAt: Date = Date(),
         pinnedAt: Date? = nil) {
        self.id = id
        self.type = type
        self.text = text
        self.textFileName = nil
        self.textPrefix = nil
        self.rtfFileName = rtfFileName
        self.htmlFileName = htmlFileName
        self.pendingRTF = pendingRTF
        self.pendingHTML = pendingHTML
        self.imageFileName = imageFileName
        self.imageHash = imageHash
        self.fileURLs = fileURLs
        self.colorHex = colorHex
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.customTitle = customTitle
        self.list = list
        self.createdAt = createdAt
        self.pinnedAt = pinnedAt
        refreshDerivedState()
    }

    /// Whether the clip sits on a pinboard.
    ///
    /// Pinning does not remove a clip from history: Paste keeps the record in
    /// clipboard history and adds the pin on top, so every clip the store holds
    /// is a history entry and `list` only names the board it is also on.
    var isPinned: Bool { list != nil }

    var charCount: Int { textCount }

    /// Recomputes the cache-only fields. Call after mutating anything they read.
    ///
    /// `createdAt` is stamped in so a promoted clip (same content, new copy
    /// time) also refreshes its band timestamp. `nonisolated` because decoding
    /// runs off the main actor.
    nonisolated mutating func refreshDerivedState(now: Date = Date()) {
        let source = text ?? textPrefix
        searchTextLowercased = Self.searchHaystack(for: self, text: source)
        cachedDisplayTitle = computeDisplayTitle()
        cachedRelativeDate = Self.relativeDate(for: createdAt, now: now)
        cachedPreviewText = Self.previewText(source)
        // A spilled clip has no full text in memory. Rehashing would hash the
        // prefix and collapse distinct pastes that share a head.
        guard text != nil || textFileName == nil else { return }
        if let text, (type == .text || type == .richText || type == .link) {
            textCount = text.count
            textPrefix = Self.storedPrefix(text)
        } else if textFileName == nil, type == .text || type == .richText || type == .link {
            textCount = 0
            textPrefix = nil
        }
        contentHash = Self.hashContent(self)
    }

    private nonisolated static func storedPrefix(_ text: String) -> String {
        let head = text.prefix(searchHaystackLimit)
        return head.endIndex == text.endIndex ? text : String(head)
    }

    private nonisolated static func searchHaystack(for item: ClipItem, text: String?) -> String {
        var haystack = ""
        func append(_ part: String) {
            guard haystack.count < searchHaystackLimit else { return }
            if !haystack.isEmpty { haystack.append(" ") }
            let room = searchHaystackLimit - haystack.count
            guard room > 0 else { return }
            haystack.append(contentsOf: part.prefix(room))
        }
        if let customTitle = item.customTitle { append(customTitle) }
        if let text { append(text) }
        if let sourceAppName = item.sourceAppName { append(sourceAppName) }
        if !item.fileURLs.isEmpty { append(item.fileURLs.joined(separator: " ")) }
        if let colorHex = item.colorHex { append(colorHex) }
        return haystack.lowercased()
    }

    private nonisolated static func previewText(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "" }
        let head = text.prefix(previewTextLimit)
        return head.endIndex == text.endIndex ? text : String(head)
    }

    private nonisolated static func hashContent(_ item: ClipItem) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        func mix(_ string: String) {
            for byte in string.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
            hash ^= 0xFF
            hash &*= 1_099_511_628_211
        }
        func mixOptional(_ string: String?) {
            if let string {
                hash ^= 1
                mix(string)
            } else {
                hash ^= 2
            }
        }
        mix(item.type.rawValue)
        switch item.type {
        case .image:
            mixOptional(item.imageHash ?? item.imageFileName)
        case .color:
            mixOptional(item.colorHex)
        case .file:
            for url in item.fileURLs { mix(url) }
        case .text, .richText, .link:
            mixOptional(item.text)
        }
        return hash
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
            return text ?? textPrefix
        }
    }

    var displayTitle: String { cachedDisplayTitle }

    private nonisolated func computeDisplayTitle() -> String {
        if let t = customTitle, !t.isEmpty { return t }
        switch type {
        case .link:
            if let t = text ?? textPrefix, let url = URL(string: t.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return url.host ?? t
            }
            return text ?? textPrefix ?? L("Link")
        case .image:
            return L("Image")
        case .file:
            return fileURLs.first.flatMap { URL(string: $0)?.lastPathComponent } ?? L("File")
        case .color:
            return colorHex ?? L("Color")
        default:
            let firstLine = (text ?? textPrefix ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
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
            if let text, let otherText = other.text { return text == otherText }
            return contentHash == other.contentHash
        }
    }

    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type && lhs.text == rhs.text
            && lhs.textFileName == rhs.textFileName
            && lhs.rtfFileName == rhs.rtfFileName && lhs.htmlFileName == rhs.htmlFileName
            && lhs.imageFileName == rhs.imageFileName && lhs.imageHash == rhs.imageHash
            && lhs.fileURLs == rhs.fileURLs && lhs.colorHex == rhs.colorHex
            && lhs.sourceBundleID == rhs.sourceBundleID && lhs.sourceAppName == rhs.sourceAppName
            && lhs.customTitle == rhs.customTitle && lhs.list == rhs.list
            && lhs.createdAt == rhs.createdAt && lhs.pinnedAt == rhs.pinnedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, text, textFileName, textPrefix, textCount, contentHash
        case rtfFileName, htmlFileName, rtfData, htmlData, imageFileName, imageHash
        case fileURLs, colorHex, sourceBundleID, sourceAppName, customTitle
        case list, createdAt, pinnedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        if textFileName == nil { try c.encodeIfPresent(text, forKey: .text) }
        try c.encodeIfPresent(textFileName, forKey: .textFileName)
        try c.encodeIfPresent(textPrefix, forKey: .textPrefix)
        if textCount > 0 { try c.encode(textCount, forKey: .textCount) }
        try c.encode(contentHash, forKey: .contentHash)
        try c.encodeIfPresent(rtfFileName, forKey: .rtfFileName)
        try c.encodeIfPresent(htmlFileName, forKey: .htmlFileName)
        try c.encodeIfPresent(imageFileName, forKey: .imageFileName)
        try c.encodeIfPresent(imageHash, forKey: .imageHash)
        try c.encode(fileURLs, forKey: .fileURLs)
        try c.encodeIfPresent(colorHex, forKey: .colorHex)
        try c.encodeIfPresent(sourceBundleID, forKey: .sourceBundleID)
        try c.encodeIfPresent(sourceAppName, forKey: .sourceAppName)
        try c.encodeIfPresent(customTitle, forKey: .customTitle)
        try c.encodeIfPresent(list, forKey: .list)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(pinnedAt, forKey: .pinnedAt)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        type = try c.decode(ClipType.self, forKey: .type)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        textFileName = try c.decodeIfPresent(String.self, forKey: .textFileName)
        textPrefix = try c.decodeIfPresent(String.self, forKey: .textPrefix)
        textCount = try c.decodeIfPresent(Int.self, forKey: .textCount) ?? text?.count ?? 0
        contentHash = try c.decodeIfPresent(UInt64.self, forKey: .contentHash) ?? 0
        rtfFileName = try c.decodeIfPresent(String.self, forKey: .rtfFileName)
        htmlFileName = try c.decodeIfPresent(String.self, forKey: .htmlFileName)
        pendingRTF = rtfFileName == nil ? try c.decodeIfPresent(Data.self, forKey: .rtfData) : nil
        pendingHTML = htmlFileName == nil ? try c.decodeIfPresent(Data.self, forKey: .htmlData) : nil
        imageFileName = try c.decodeIfPresent(String.self, forKey: .imageFileName)
        imageHash = try c.decodeIfPresent(String.self, forKey: .imageHash)
        fileURLs = try c.decodeIfPresent([String].self, forKey: .fileURLs) ?? []
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
        sourceBundleID = try c.decodeIfPresent(String.self, forKey: .sourceBundleID)
        sourceAppName = try c.decodeIfPresent(String.self, forKey: .sourceAppName)
        customTitle = try c.decodeIfPresent(String.self, forKey: .customTitle)
        list = try c.decodeIfPresent(UUID.self, forKey: .list)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        pinnedAt = try c.decodeIfPresent(Date.self, forKey: .pinnedAt)
        refreshDerivedState()
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
