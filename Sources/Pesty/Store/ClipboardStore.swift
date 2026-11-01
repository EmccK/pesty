import AppKit
import Observation
import os

extension Notification.Name {
    static let pestyStoreDidSave = Notification.Name("PestyStoreDidSave")
}

enum BarSource: Equatable {
    case history
    case pinboard(UUID)
}

/// Whether keyboard focus currently belongs to the native search field or
/// to the clip strip. Lets the key monitor and the search field agree on
/// who owns a given keystroke without probing AppKit's first-responder
/// chain from every call site.
enum BarInputMode: Equatable {
    case cards
    case search
}

/// One object per clip so a selection change notifies the two cards whose
/// flag flipped. A shared `selectedID` would invalidate every card that read it.
@Observable
final class SelectionFlag {
    var isSelected = false
}

@Observable
@MainActor
final class ClipboardStore {
    static let shared = ClipboardStore()

    /// Every clip the app knows about, in one table.
    ///
    /// Paste keeps a single record per copied thing and points it at the
    /// clipboard list or at a pinboard, instead of copying the content into a
    /// second container. Pinning therefore repoints a field; it never duplicates
    /// the clip or its image file, and "is this pinned?" is a property of the
    /// clip rather than a lookup across boards.
    ///
    /// Ordered newest-copied first, which is the history order. A pinboard's
    /// order comes from `pinnedAt`, so one array serves both views.
    private(set) var items: [ClipItem] = [] {
        didSet {
            invalidateVisibleItems()
            indexIsStale = true
        }
    }

    /// Boards carry no clips of their own any more: membership lives on the
    /// clip as `ClipItem.list`.
    private(set) var pinboards: [Pinboard] = [] {
        didSet { invalidateVisibleItems() }
    }

    private var undoStack = ClipUndoStack()
    /// True while a deletion can still be undone; drives the bar's Undo button.
    private(set) var hasUndoableDeletion = false
    private var undoExpirationWorkItem: DispatchWorkItem?

    var source: BarSource = .history {
        didSet {
            if source != oldValue { clearMultiSelection(); invalidateVisibleItems() }
        }
    }
    var barInputMode: BarInputMode = .cards
    var searchText: String = "" {
        didSet {
            if searchText != oldValue { clearMultiSelection(); invalidateVisibleItems() }
        }
    }
    var selectedID: UUID? {
        didSet { if selectedID != oldValue { refreshSelectionFlags() } }
    }
    private(set) var multiSelectedIDs: Set<UUID> = [] {
        didSet { if multiSelectedIDs != oldValue { refreshSelectionFlags() } }
    }
    private var selectionAnchorID: UUID?

    /// Set while the user is arrowing through the strip. Keyboard moves arrive
    /// faster than a 0.2 s scroll tween can finish, so the strip jumps instead
    /// of queueing overlapping animations while this is true; a click or a
    /// presentation reset clears it and gets the smooth scroll back.
    private(set) var isFastSelectionRun = false
    private var fastSelectionReset: DispatchWorkItem?

    /// Bumped every time the bar is about to present. The hosting view is
    /// built once and cached, so the strip keeps its scroll offset across
    /// hide/show; selection alone cannot reset it because the newest clip is
    /// usually already selected and `onChange` never fires for equal values.
    private(set) var barPresentationToken = 0

    private var storeURL: URL
    private var imagesDir: URL
    private var blobsDir: URL
    private var baseDir: URL
    private var saveWorkItem: DispatchWorkItem?

    private var fileWatch: DispatchSourceFileSystemObject?
    /// Bytes of the last snapshot this process wrote, so the file watch can
    /// tell this app's own save from another Mac's.
    private nonisolated static let lastWritten = OSAllocatedUnfairLock<Data?>(initialState: nil)

    /// Clip and board ids deleted here, with when. Another Mac merging this
    /// file drops them instead of syncing them back.
    private var tombstones: [String: Date] = [:]
    private static let tombstoneRetention: TimeInterval = 30 * 86_400

    /// Set when the store file exists but could not be read. Saving would
    /// overwrite history this launch never saw, so it stays off.
    private var storeIsReadOnly = false
    /// Shown once at launch when the history file was unreadable.
    private(set) var launchNotice: String?

    static var localBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pesty", isDirectory: true)
    }

    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    static var iCloudBase: URL? {
        guard !isSandboxed else { return nil }
        let p = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: p.path) else { return nil }
        return p.appendingPathComponent("Pesty", isDirectory: true)
    }

    var iCloudAvailable: Bool { ClipboardStore.iCloudBase != nil }

    /// The on-disk store root (history JSON plus saved images), exposed so
    /// Settings can report how much space history actually uses.
    var dataDirectory: URL { baseDir }

    private init() {
        let base = (Settings.shared.iCloudSync ? ClipboardStore.iCloudBase : nil) ?? ClipboardStore.localBase
        baseDir = base
        imagesDir = base.appendingPathComponent("images", isDirectory: true)
        blobsDir = base.appendingPathComponent("blobs", isDirectory: true)
        storeURL = base.appendingPathComponent("store.json")
        prepareDirectories()
        load()
        if Settings.shared.iCloudSync { startWatching() }
    }

    private func prepareDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try? fm.createDirectory(at: blobsDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: baseDir.path)
    }

    // MARK: - Collections

    /// Boards and clips share one table: history is `items`, and `list` names
    /// the board a clip is also on, so "the history" and "the clips on a board"
    /// are the same array read two ways.

    func pinboard(of item: ClipItem) -> Pinboard? {
        guard let list = item.list else { return nil }
        return pinboards.first(where: { $0.id == list })
    }

    /// Cached result of the `source` + `searchText` projection over the store's
    /// clips.
    ///
    /// The strip asks for this repeatedly in a single layout pass — the list
    /// itself, the animation key, the empty state — and every card used to ask
    /// for its own position, which walked the whole array again. The projection
    /// is now paid once per change to its inputs instead of once per reader.
    ///
    /// Invalidation is by writer, not by caller: `items`, `pinboards`, `source`
    /// and `searchText` each clear it in their own `didSet`, so no mutation site
    /// has to remember to. `didSet` fires for in-place array mutation too
    /// (`insert`, `remove`, `removeAll`), which is how the store edits clips.
    private var cachedVisibleItems: [ClipItem]?
    /// Position of each clip in `cachedVisibleItems`, so a card's ⌘-number
    /// hint costs a dictionary lookup instead of a linear scan.
    ///
    /// `@ObservationIgnored` on every cache below: all of them are written
    /// while cards are on screen, so a card that subscribed to one would
    /// invalidate on each write. Readers depend on `cachedVisibleItems`, the
    /// one cache whose invalidation means "the strip changed".
    @ObservationIgnored private var cachedVisibleIndex: [UUID: Int] = [:]
    @ObservationIgnored private var cachedVisibleIDs: [UUID] = []
    @ObservationIgnored private var indexByID: [UUID: Int] = [:]
    @ObservationIgnored private var indexByContent: [UInt64: Int] = [:]
    @ObservationIgnored private var indexIsStale = true
    /// One flag per clip, so a selection change repaints the two cards whose
    /// flag flipped. The dictionary itself must stay unobserved: as observed
    /// state, assigning it invalidated every card in the strip - which is what
    /// the per-clip flag exists to avoid.
    @ObservationIgnored private var selectionFlags: [UUID: SelectionFlag] = [:]
    private let saveQueue = DispatchQueue(label: "pesty.save", qos: .utility)

    private func invalidateVisibleItems() {
        cachedVisibleItems = nil
        cachedVisibleIndex = [:]
    }

    /// The clips the bar is currently showing: the selected pinboard or the
    /// history, narrowed by the search field.
    var visibleItems: [ClipItem] {
        if let cachedVisibleItems { return cachedVisibleItems }
        let base: [ClipItem]
        switch source {
        case .history:
            base = items
        case .pinboard(let id):
            base = items
                .filter { $0.list == id }
                .sorted { ($0.pinnedAt ?? $0.createdAt) > ($1.pinnedAt ?? $1.createdAt) }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let result = q.isEmpty ? base : base.filter { $0.searchTextLowercased.contains(q) }
        cachedVisibleItems = result
        var index = [UUID: Int](minimumCapacity: result.count)
        var ids: [UUID] = []
        ids.reserveCapacity(result.count)
        for (position, clip) in result.enumerated() {
            index[clip.id] = position
            ids.append(clip.id)
        }
        cachedVisibleIndex = index
        cachedVisibleIDs = ids
        return result
    }

    var visibleIDs: [UUID] {
        if cachedVisibleItems == nil { _ = visibleItems }
        return cachedVisibleIDs
    }

    var selectedItem: ClipItem? {
        guard let id = selectedID else { return nil }
        let items = visibleItems
        guard let idx = cachedVisibleIndex[id] else { return nil }
        return items[idx]
    }

    // MARK: - Capture

    func addCaptured(_ item: ClipItem) {
        var incoming = item
        // A fresh capture is a new history entry, so it carries no pin. Copying
        // something that is already on a board does not unpin it - the record
        // that gets bumped to the front keeps its `list`.
        incoming.list = nil
        incoming.pinnedAt = nil
        if let idx = duplicateIndex(of: incoming) {
            releaseFiles(of: [incoming])
            var existing = items.remove(at: idx)
            existing.createdAt = incoming.createdAt
            existing.refreshDerivedState()
            items.insert(existing, at: 0)
            if source == .history && searchText.isEmpty && multiSelectedIDs.isEmpty {
                selectedID = existing.id
                selectionAnchorID = existing.id
            }
            scheduleSave()
            return
        }
        items.insert(incoming, at: 0)
        spill(&items[0])
        trimHistory()
        if source == .history && searchText.isEmpty && multiSelectedIDs.isEmpty {
            selectedID = incoming.id
            selectionAnchorID = incoming.id
        }
        scheduleSave()
    }

    /// A Copy from the Paste Bar is an intentional use of an existing clip.
    /// Promote it explicitly because the clipboard monitor correctly ignores
    /// Pesty's own pasteboard writes, so a plain re-copy would otherwise leave
    /// the clip sitting wherever it already was in history.
    ///
    /// There is one record per clip, so promoting only re-stamps its copy time
    /// and moves it to the front of history. A pinned clip keeps its board.
    func promoteCopiedItem(_ item: ClipItem, at date: Date = .now) {
        guard let idx = itemIndex(of: item.id) else {
            var copy = item
            copy.createdAt = date
            addCaptured(copy)
            return
        }
        var promoted = items.remove(at: idx)
        promoted.createdAt = date
        promoted.refreshDerivedState()
        items.insert(promoted, at: 0)
        scheduleSave()
    }

    // MARK: - Retention

    func applyRetentionPolicy() {
        let before = items.count
        trimHistory()
        if items.count != before { scheduleSave() }
    }

    func retentionRemovalCount(mode: HistoryRetentionMode, limit: Int, days: Int) -> Int {
        let pruneable = items.filter { !$0.isPinned }
        switch mode {
        case .itemCount:
            return max(0, pruneable.count - max(20, limit))
        case .timeInterval:
            // days == 0 means "forever" - no age-based cutoff, just the safety cap.
            guard let cutoff = Self.retentionCutoff(daysAgo: days) else {
                return max(0, pruneable.count - Self.timeRetentionSafetyCap)
            }
            let byAge = pruneable.filter { $0.createdAt < cutoff }.count
            return byAge + max(0, (pruneable.count - byAge) - Self.timeRetentionSafetyCap)
        }
    }

    private static let timeRetentionSafetyCap = 5000

    private static func retentionCutoff(daysAgo days: Int) -> Date? {
        guard days > 0 else { return nil }
        return Date().addingTimeInterval(-TimeInterval(days) * 86_400)
    }

    private(set) var retentionPrunedRecordNames: Set<String> = []

    func isRetentionPruned(_ recordName: String) -> Bool {
        retentionPrunedRecordNames.contains(recordName)
    }

    /// Trims history, skipping pinned clips.
    ///
    /// A pinned clip is still a history entry, so the limit counts only the
    /// clips that are not on a board - otherwise filling a pinboard would
    /// silently push real history out. This matches Paste's own promise on its
    /// history-limit alert: "Pinned items and Pinboards won't be deleted."
    private func trimHistory() {
        var removed: [ClipItem] = []
        let pruneable = items.indices.filter { !items[$0].isPinned }
        let historyLimit = Settings.shared.historyLimit
        switch Settings.shared.historyRetentionMode {
        case .itemCount:
            if pruneable.count > historyLimit {
                removed = pruneable.dropFirst(historyLimit).map { items[$0] }
            }
        case .timeInterval:
            // days == 0 means "forever" - skip the age cutoff, keep the safety cap.
            if let cutoff = Self.retentionCutoff(daysAgo: Settings.shared.historyRetentionDays) {
                removed += pruneable.map { items[$0] }.filter { $0.createdAt < cutoff }
            }
            let survivors = pruneable.count - removed.count
            if survivors > Self.timeRetentionSafetyCap {
                let keep = Set(pruneable.map { items[$0].id }
                    .prefix(Self.timeRetentionSafetyCap))
                removed += pruneable.map { items[$0] }.filter { !keep.contains($0.id) }
            }
        }
        guard !removed.isEmpty else { return }
        let ids = Set(removed.map(\.id))
        items.removeAll { ids.contains($0.id) }
        releaseFiles(of: removed)
        // Deliberately no tombstone: retention prunes this Mac's history, and
        // a second Mac's copy of the same clip is not this Mac's to delete.
        markRetentionPruned(removed)
        if let sel = selectedID, ids.contains(sel) { selectFirst() }
        reconcileMultiSelection()
    }

    private func markRetentionPruned(_ items: [ClipItem]) {
        let names = items.map { $0.id.uuidString }
        retentionPrunedRecordNames.formUnion(names)
        #if MAS
        CloudSyncService.shared.retainRemoteRecords(named: names)
        #endif
    }

    // MARK: - Deletion

    /// Deletes the record itself, wherever it is being shown.
    ///
    /// A clip is one record that history and at most one board both point at,
    /// so deleting it from a board has to take it out of history too - this is
    /// Paste's `delete_item`, which "removes the underlying record for good"
    /// from both. Unpinning is the separate, non-destructive action
    /// (`remove_item_from_pinboard`), and it has its own menu item.
    func delete(_ item: ClipItem, permanently: Bool = false) {
        delete(items: [item], permanently: permanently)
    }

    /// A deletion stays undoable for five minutes unless `permanently` is
    /// set for this one (Option was held) or the setting says so for all.
    func delete(items targets: [ClipItem], permanently: Bool = false) {
        let ids = Set(targets.map(\.id))
        guard !ids.isEmpty else { return }
        // Captured before removal so repeated deletes walk down the list
        // instead of snapping back to the newest clip every time.
        let deletedIndex = visibleItems.firstIndex(where: { ids.contains($0.id) })
        let selectionDeleted = selectedID.map { ids.contains($0) } ?? false

        let placements = Self.placements(of: ids, in: items, container: source)
        items.removeAll { ids.contains($0.id) }
        recordTombstones(ids)
        // The record is gone, so its files can go too - unless the undo stack
        // is still holding them for a restore.
        if permanently || Settings.shared.deletePermanently {
            releaseFiles(of: placements.map(\.item))
        }
        // Permanent deletes are not undoable.
        if !permanently && !Settings.shared.deletePermanently {
            undoStack.push(placements, at: Date())
            refreshUndoState()
        }

        multiSelectedIDs.subtract(ids)
        if multiSelectedIDs.count <= 1 { multiSelectedIDs = [] }
        if selectionDeleted {
            let remaining = visibleItems
            if let index = deletedIndex, !remaining.isEmpty {
                selectedID = remaining[min(index, remaining.count - 1)].id
            } else {
                selectFirst()
            }
            selectionAnchorID = selectedID
        }
        reconcileMultiSelection()
        scheduleSave()
    }

    /// Erases history, sparing anything pinned.
    ///
    /// Pinned clips are history entries too, but Paste's erase-history alert
    /// promises "Pinned items and Pinboards won't be deleted", so they stay -
    /// on their boards, and in the history list.
    func clearHistory() {
        let cleared = items.filter { !$0.isPinned }
        let ids = Set(cleared.map(\.id))
        items.removeAll { ids.contains($0.id) }
        selectedID = nil
        forgetDeletions()
        recordTombstones(ids)
        releaseFiles(of: cleared)
        reconcileMultiSelection()
        scheduleSave()
    }

    private static func placements(of ids: Set<UUID>, in items: [ClipItem],
                                   container: BarSource) -> [ClipPlacement] {
        items.indices.compactMap { index in
            guard ids.contains(items[index].id) else { return nil }
            return ClipPlacement(container: container,
                                 index: index,
                                 item: items[index],
                                 predecessorID: index > 0 ? items[index - 1].id : nil,
                                 successorID: index + 1 < items.count ? items[index + 1].id : nil)
        }
    }

    // MARK: - Undo

    /// Puts the newest deletion back where it was, every clip of a bulk
    /// delete at once, while its five-minute window is open.
    @discardableResult
    func undoLastDelete() -> Bool {
        refreshUndoState()
        guard let deletion = undoStack.pop(at: Date()) else { return false }
        var restored: [UUID] = []
        for placement in deletion.placements.sorted(by: { $0.index < $1.index }) {
            if restore(placement) { restored.append(placement.item.id) }
        }
        refreshUndoState()
        // The clip is back, so the tombstone that recorded its deletion has to
        // go: otherwise the next merge reads it as deleted and removes it again
        // on every Mac that has not seen the undo.
        for id in restored { tombstones.removeValue(forKey: id.uuidString) }
        if let id = restored.first(where: { id in visibleItems.contains(where: { $0.id == id }) }) {
            selectedID = id
            selectionAnchorID = id
        }
        reconcileMultiSelection()
        scheduleSave()
        return true
    }

    /// A clip that came back by other means in the meantime (copied again,
    /// or synced in) is left as it is rather than doubled.
    private func restore(_ placement: ClipPlacement) -> Bool {
        var item = placement.item
        switch placement.container {
        case .history:
            // Undoing a real delete restores the record as it was, pin
            // included: deleting from history removes the clip from its board
            // too, so bringing it back has to put the pin back as well.
            break
        case .pinboard(let boardID):
            guard pinboards.contains(where: { $0.id == boardID }) else {
                releaseFiles(of: [item])
                return false
            }
            item.list = boardID
        }
        let already = itemIndex(of: item.id) != nil || duplicateIndex(of: item) != nil
        if already {
            releaseFiles(of: [item])
            return false
        }
        items.insert(item, at: Self.historyInsertionIndex(for: item, in: items))
        return true
    }

    /// Newest-copied first, which is the order history is read in.
    private static func historyInsertionIndex(for item: ClipItem, in items: [ClipItem]) -> Int {
        items.firstIndex(where: { $0.createdAt < item.createdAt }) ?? items.endIndex
    }

    /// Drops deletions whose window has closed, releasing the image files
    /// they kept, and arms a timer for the next one so the Undo button
    /// retires on time.
    private func refreshUndoState() {
        let now = Date()
        for deletion in undoStack.removeExpired(at: now) {
            releaseFiles(of: deletion.placements.map(\.item))
        }
        hasUndoableDeletion = !undoStack.isEmpty
        undoExpirationWorkItem?.cancel()
        undoExpirationWorkItem = nil
        guard let expiration = undoStack.nextExpiration else { return }
        let work = DispatchWorkItem { [weak self] in self?.refreshUndoState() }
        undoExpirationWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, expiration.timeIntervalSince(now)),
                                      execute: work)
    }

    /// Clear History and removing a Pinboard are the moments deleted content
    /// is expected to be gone for good, so nothing stays restorable. Quitting
    /// forgets as well, since the stack does not outlive the process and the
    /// image files it kept would otherwise be orphaned.
    func forgetDeletions() {
        for deletion in undoStack.removeAll() {
            releaseFiles(of: deletion.placements.map(\.item))
        }
        refreshUndoState()
    }

    // MARK: - Pinboards

    @discardableResult
    func addPinboard(name: String, colorHex: String = Pinboard.randomColorHex) -> Pinboard {
        let b = Pinboard(name: name, colorHex: colorHex)
        pinboards.append(b)
        scheduleSave()
        return b
    }

    func renamePinboard(_ id: UUID, to name: String) {
        guard let i = pinboards.firstIndex(where: { $0.id == id }) else { return }
        pinboards[i].name = name
        scheduleSave()
    }

    /// Recolors a board. Every card in it reads the color off the board, so the
    /// strip only has to re-render - nothing about the clips changes.
    func setPinboardColor(_ hex: String, for id: UUID) {
        guard let i = pinboards.firstIndex(where: { $0.id == id }) else { return }
        guard pinboards[i].colorHex != hex else { return }
        pinboards[i].colorHex = hex
        scheduleSave()
    }

    /// Removes the board, not the clips. Every clip pinned to it goes back to
    /// being history-only, which is what Paste promises when a pinboard is
    /// deleted: the items stay in clipboard history.
    func deletePinboard(_ id: UUID) {
        guard let i = pinboards.firstIndex(where: { $0.id == id }) else { return }
        if case .pinboard(let cur) = source, cur == id { source = .history }
        pinboards.remove(at: i)
        recordTombstones([id])
        for index in items.indices where items[index].list == id {
            items[index].list = nil
            items[index].pinnedAt = nil
        }
        reconcileMultiSelection()
        scheduleSave()
    }

    /// Pins the clip to a board by repointing it. No copy is made: the clip
    /// keeps its id, its image file and its place in history, so pinning and
    /// unpinning are reversible without leaving duplicates behind.
    ///
    /// Pinning to a second board moves the clip, because a clip is on one board
    /// at a time - the same cardinality Paste's `ItemEntity.list` has.
    func saveToPinboard(_ item: ClipItem, boardID: UUID) {
        guard pinboards.contains(where: { $0.id == boardID }) else { return }
        guard let index = itemIndex(of: item.id) else { return }
        guard items[index].list != boardID else { return }
        items[index].list = boardID
        items[index].pinnedAt = Date()
        scheduleSave()
    }

    /// Takes the clip off its board. It stays in history.
    func removeFromPinboard(_ item: ClipItem) {
        guard let index = itemIndex(of: item.id) else { return }
        guard items[index].list != nil else { return }
        items[index].list = nil
        items[index].pinnedAt = nil
        scheduleSave()
    }

    func item(withID id: UUID) -> ClipItem? {
        guard let index = itemIndex(of: id) else { return nil }
        return items[index]
    }

    private func itemIndex(of id: UUID) -> Int? {
        reindexIfNeeded()
        return indexByID[id]
    }

    /// Hash hit confirms with `sameContent`. A miss is new content: no scan.
    /// ponytail: a 64-bit FNV collision scans. Irrelevant at clipboard scale.
    private func duplicateIndex(of item: ClipItem) -> Int? {
        reindexIfNeeded()
        guard let idx = indexByContent[item.contentHash] else { return nil }
        if items.indices.contains(idx), items[idx].sameContent(as: item) { return idx }
        return items.firstIndex { $0.sameContent(as: item) }
    }

    private func reindexIfNeeded() {
        guard indexIsStale else { return }
        indexIsStale = false
        var byID = [UUID: Int](minimumCapacity: items.count)
        var byContent = [UInt64: Int](minimumCapacity: items.count)
        for (offset, item) in items.enumerated() {
            byID[item.id] = offset
            byContent[item.contentHash] = offset
        }
        indexByID = byID
        indexByContent = byContent
        if selectionFlags.count > items.count + 128 {
            let live = Set(items.map(\.id))
            selectionFlags = selectionFlags.filter { live.contains($0.key) }
        }
    }

    // MARK: - Content edits

    @discardableResult
    func updateTextContent(_ text: String, richTextData: Data? = nil, for item: ClipItem) -> Bool {
        guard [.text, .richText, .link].contains(item.type),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let type: ClipType = richTextData != nil ? .richText : (ClipType.isWebLink(text) ? .link : .text)
        let newRTF = richTextData.flatMap { storeBlob($0, ext: "rtf") }
        let previousRTF = item.rtfFileName
        let previousHTML = item.htmlFileName
        let previousText = item.textFileName
        if richTextData == nil, item.htmlFileName == nil, item.type == type, fullText(for: item) == text {
            return false
        }
        let ok = updateContent(of: item) { existing in
            var updated = existing
            updated.type = type
            updated.text = text
            updated.textFileName = nil
            updated.rtfFileName = newRTF
            updated.htmlFileName = nil
            updated.colorHex = nil
            return updated
        }
        if ok {
            spill(&items[0])
            deleteBlobsIfUnused([previousText, previousRTF, previousHTML])
        } else if newRTF != previousRTF {
            deleteBlobsIfUnused([newRTF])
        }
        return ok
    }

    @discardableResult
    func updateColorContent(_ hex: String, for item: ClipItem) -> Bool {
        guard item.type == .color, let color = NSColor(hex: hex) else { return false }
        let normalized = color.hexString
        let previousRTF = item.rtfFileName
        let previousHTML = item.htmlFileName
        let previousText = item.textFileName
        let ok = updateContent(of: item) { existing in
            var updated = existing
            updated.type = .color
            updated.text = nil
            updated.textFileName = nil
            updated.rtfFileName = nil
            updated.htmlFileName = nil
            updated.colorHex = normalized
            return updated
        }
        if ok {
            deleteBlobsIfUnused([previousRTF, previousHTML, previousText])
        }
        return ok
    }

    private func updateContent(of item: ClipItem, transform: (ClipItem) -> ClipItem) -> Bool {
        guard let i = itemIndex(of: item.id) else { return false }
        var updated = transform(items[i])
        guard updated != items[i] else { return false }
        updated.createdAt = Date()
        updated.refreshDerivedState()
        items.remove(at: i)
        removeContentDuplicates(of: updated)
        items.insert(updated, at: 0)

        retentionPrunedRecordNames.remove(item.id.uuidString)
        if selectedItem == nil { selectFirst() }
        reconcileMultiSelection()
        scheduleSave()
        return true
    }

    /// Editing a clip's content can make it match another clip. One record per
    /// copied thing is the whole point of the single table, so content is
    /// unique across it rather than within a container: editing a clip until it
    /// matches another one has to leave one record behind, the same way
    /// capturing a duplicate does.
    private func removeContentDuplicates(of item: ClipItem) {
        let duplicates = items.filter {
            $0.id != item.id && $0.contentHash == item.contentHash && $0.sameContent(as: item)
        }
        guard !duplicates.isEmpty else { return }
        let ids = Set(duplicates.map(\.id))
        items.removeAll { ids.contains($0.id) }
        releaseFiles(of: duplicates)
    }

    func setTitle(_ title: String, for item: ClipItem) {
        guard let i = itemIndex(of: item.id) else { return }
        items[i].customTitle = title
        items[i].refreshDerivedState()
        scheduleSave()
    }

    // MARK: - Selection

    func selectFirst() {
        let first = visibleItems.first?.id
        guard selectedID != first else { return }
        selectedID = first
    }

    func selectionFlag(for id: UUID) -> SelectionFlag {
        if let flag = selectionFlags[id] { return flag }
        let flag = SelectionFlag()
        flag.isSelected = isSelected(id)
        var flags = selectionFlags
        flags[id] = flag
        selectionFlags = flags
        return flag
    }

    private func refreshSelectionFlags() {
        let onIDs: Set<UUID> = multiSelectedIDs.isEmpty
            ? Set(selectedID.map { [$0] } ?? [])
            : multiSelectedIDs
        if cachedVisibleItems != nil, !cachedVisibleIDs.isEmpty {
            let center = selectedID.flatMap { cachedVisibleIndex[$0] } ?? 0
            let lower = max(0, center - 8)
            let upper = min(cachedVisibleIDs.count, center + 32)
            var flags = selectionFlags
            var grew = false
            for id in cachedVisibleIDs[lower..<upper] where flags[id] == nil {
                let flag = SelectionFlag()
                flag.isSelected = onIDs.contains(id)
                flags[id] = flag
                grew = true
            }
            if grew { selectionFlags = flags }
        }
        for (id, flag) in selectionFlags {
            let on = onIDs.contains(id)
            if flag.isSelected != on { flag.isSelected = on }
        }
    }

    var effectiveSelectionIDs: Set<UUID> {
        if !multiSelectedIDs.isEmpty { return multiSelectedIDs }
        return selectedID.map { [$0] } ?? []
    }

    /// Position of `id` in the strip, for the ⌘1-⌘9 quick-paste hint.
    /// Returns a value past the hint range when the clip is not visible, so the
    /// hint simply does not render.
    ///
    /// Every card asks for this in its own body, so it must not walk the strip:
    /// the index is built alongside `visibleItems` and consulted here.
    func visibleIndex(of id: UUID) -> Int {
        if cachedVisibleItems == nil { _ = visibleItems }
        return cachedVisibleIndex[id] ?? Int.max
    }

    func isSelected(_ id: UUID) -> Bool {
        if multiSelectedIDs.isEmpty { return selectedID == id }
        return multiSelectedIDs.contains(id)
    }

    func select(_ id: UUID) {
        // One-click select has to be a no-op when it changes nothing. Clicking
        // an already-selected card used to write the same value back through
        // `@Observable`, which still invalidates every reader that asks for the
        // selection — the whole strip, since each card asks.
        let alreadyOnlySelection = selectedID == id
            && multiSelectedIDs.isEmpty
            && selectionAnchorID == id
        if isFastSelectionRun { isFastSelectionRun = false }
        guard !alreadyOnlySelection else { return }
        selectedID = id
        selectionAnchorID = id
        if !multiSelectedIDs.isEmpty { multiSelectedIDs = [] }
    }

    func toggleSelection(_ id: UUID) {
        _ = visibleItems
        guard cachedVisibleIndex[id] != nil else { return }
        if multiSelectedIDs.isEmpty, let sel = selectedID, sel != id,
           visibleItems.contains(where: { $0.id == sel }) {
            multiSelectedIDs = [sel]
        }
        if multiSelectedIDs.contains(id) {
            multiSelectedIDs.remove(id)
            if selectedID == id { selectedID = multiSelectedIDs.first ?? visibleItems.first?.id }
            if selectionAnchorID == id { selectionAnchorID = selectedID }
            if multiSelectedIDs.count <= 1 { multiSelectedIDs = [] }
        } else {
            multiSelectedIDs.insert(id)
            selectedID = id
            if selectionAnchorID == nil { selectionAnchorID = id }
            if multiSelectedIDs.count == 1 { multiSelectedIDs = [] }
        }
    }

    func extendSelection(to id: UUID) {
        let items = visibleItems
        guard let targetIndex = cachedVisibleIndex[id] else { return }
        guard let anchor = selectionAnchorID ?? selectedID,
              let anchorIndex = cachedVisibleIndex[anchor] else {
            select(id)
            return
        }
        let range = items[min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)]
        multiSelectedIDs = Set(range.map(\.id))
        selectedID = id
        selectionAnchorID = anchor
        if multiSelectedIDs.count <= 1 { multiSelectedIDs = [] }
    }

    func clearMultiSelection() {
        guard !multiSelectedIDs.isEmpty || selectionAnchorID != selectedID else { return }
        multiSelectedIDs = []
        selectionAnchorID = selectedID
    }

    /// Selects every clip the strip is showing. A single visible clip goes
    /// through `select` so the multi-selection set stays empty.
    func selectAllVisible() {
        let ids = visibleIDs
        guard let first = ids.first else { return }
        if ids.count == 1 {
            select(first)
            return
        }
        let all = Set(ids)
        if multiSelectedIDs == all { return }
        let anchor = selectedID.flatMap { all.contains($0) ? $0 : nil } ?? first
        multiSelectedIDs = all
        selectedID = anchor
        selectionAnchorID = anchor
    }

    private func reconcileMultiSelection() {
        guard !multiSelectedIDs.isEmpty else { return }
        let visible = Set(visibleItems.map(\.id))
        multiSelectedIDs.formIntersection(visible)
        if multiSelectedIDs.count <= 1 { multiSelectedIDs = [] }
        if let anchor = selectionAnchorID, !visible.contains(anchor) {
            selectionAnchorID = selectedID
        }
        if let sel = selectedID, !visible.contains(sel) {
            selectedID = multiSelectedIDs.first ?? visibleItems.first?.id
        }
    }

    func prepareForBarPresentation() {
        applyRetentionPolicy()
        refreshVisibleAges()
        clearMultiSelection()
        barPresentationToken &+= 1
        selectFirst()
        refreshSelectionFlags()
        warmPreviews()
    }

    /// A band's age is cached at capture, so without this every clip copied in
    /// this session kept reading "Just now" until its content changed.
    /// ponytail: the 64 newest cards only. Formatting all 5000 costs 40 ms,
    /// and this runs on the hotkey path.
    private func refreshVisibleAges() {
        let now = Date()
        let indices = visibleIDs.prefix(64).compactMap { itemIndex(of: $0) }
        for index in indices { items[index].refreshRelativeDate(now: now) }
    }

    private func warmPreviews() {
        var pending: [ClipItem] = []
        for item in visibleItems where ClipPreviewProvider.showsImage(item) {
            pending.append(item)
            if pending.count == 16 { break }
        }
        ClipPreviewProvider.warm(pending)
    }

    func moveSelection(by delta: Int) {
        if !multiSelectedIDs.isEmpty { multiSelectedIDs = [] }
        let items = visibleItems
        guard !items.isEmpty else { return }
        guard let id = selectedID, let idx = cachedVisibleIndex[id] else {
            let first = items[0].id
            if selectedID != first { selectedID = first }
            if selectionAnchorID != selectedID { selectionAnchorID = selectedID }
            return
        }
        let next = max(0, min(items.count - 1, idx + delta))
        guard next != idx else { return }
        selectedID = items[next].id
        selectionAnchorID = selectedID
        beginFastSelectionRun()
    }

    /// Starts (or extends) the window where scroll requests snap rather than
    /// animate, so a held arrow key produces one visible move instead of a
    /// pile of half-finished ones.
    private func beginFastSelectionRun() {
        if !isFastSelectionRun { isFastSelectionRun = true }
        fastSelectionReset?.cancel()
        let reset = DispatchWorkItem { [weak self] in
            self?.isFastSelectionRun = false
        }
        fastSelectionReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: reset)
    }

    // MARK: - Images

    var imagesDirectory: URL { imagesDir }

    nonisolated static func writeImage(_ data: Data, to directory: URL) -> String? {
        writeBlob(data, ext: "png", to: directory)
    }

    func imageURL(for item: ClipItem) -> URL? {
        guard let name = item.imageFileName else { return nil }
        return imagesDir.appendingPathComponent(name)
    }

    func loadImage(for item: ClipItem) -> NSImage? {
        guard let url = imageURL(for: item) else { return nil }
        return NSImage(contentsOf: url)
    }

    func storeImageData(_ data: Data) -> String? {
        Self.writeImage(data, to: imagesDir)
    }

    /// Every file name a surviving clip or an undoable deletion still points
    /// at. Built once per batch: checking file by file walked the whole table
    /// for each removed clip, which made Clear History quadratic.
    private func liveFileNames() -> Set<String> {
        var names = undoStack.retainedFileNames
        for item in items { names.formUnion(item.ownedFileNames) }
        return names
    }

    /// Deletes the files a batch of removed clips owns, keeping anything a
    /// surviving clip or an undoable deletion still uses.
    private func releaseFiles(of removed: [ClipItem]) {
        guard !removed.isEmpty else { return }
        let live = liveFileNames()
        let fm = FileManager.default
        for item in removed {
            for blob in item.blobFileNames where !live.contains(blob) {
                try? fm.removeItem(at: blobsDir.appendingPathComponent(blob))
            }
            guard let image = item.imageFileName, !live.contains(image) else { continue }
            try? fm.removeItem(at: imagesDir.appendingPathComponent(image))
        }
    }

    /// Removes sidecar and image files no clip points at.
    ///
    /// Needed once for the text bodies earlier builds never deleted, and cheap
    /// enough to keep at every launch. Files under an hour old are left alone:
    /// with iCloud Drive, a clip recorded on the other Mac can arrive after its
    /// file does, and the file has to survive the gap.
    nonisolated static func pruneOrphans(in directories: [URL], live: Set<String>, modifiedBefore cutoff: Date) {
        let fm = FileManager.default
        for directory in directories {
            guard let files = try? fm.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for file in files where !live.contains(file.lastPathComponent) {
                guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate,
                      modified < cutoff else { continue }
                try? fm.removeItem(at: file)
            }
        }
    }

    var blobsDirectory: URL { blobsDir }

    func fullText(for item: ClipItem) -> String? {
        switch item.type {
        case .image:
            return nil
        case .color:
            return item.colorHex
        case .file:
            return item.plainText
        case .text, .richText, .link:
            if item.textFileName == nil, let text = item.text { return text }
            if let name = item.textFileName,
               let data = blobData(named: name),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return item.text ?? item.textPrefix
        }
    }

    func blobData(named name: String?) -> Data? {
        guard let name else { return nil }
        return try? Data(contentsOf: blobsDir.appendingPathComponent(name), options: .mappedIfSafe)
    }

    func blobByteCount(named name: String?) -> Int? {
        guard let name else { return nil }
        let values = try? blobsDir.appendingPathComponent(name)
            .resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize
    }

    func storeBlob(_ data: Data, ext: String) -> String? {
        Self.writeBlob(data, ext: ext, to: blobsDir)
    }

    nonisolated static func writeBlob(_ data: Data, ext: String, to directory: URL) -> String? {
        let name = "\(UUID().uuidString).\(ext)"
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return name
        } catch { return nil }
    }

    /// Drops the blobs an edit replaced, unless something else still points at them.
    private func deleteBlobsIfUnused(_ names: [String?]) {
        let live = liveFileNames()
        for case let name? in names where !live.contains(name) {
            try? FileManager.default.removeItem(at: blobsDir.appendingPathComponent(name))
        }
    }

    private func spill(_ item: inout ClipItem) {
        if let data = item.pendingRTF {
            item.rtfFileName = storeBlob(data, ext: "rtf") ?? item.rtfFileName
            item.pendingRTF = nil
        }
        if let data = item.pendingHTML {
            item.htmlFileName = storeBlob(data, ext: "html") ?? item.htmlFileName
            item.pendingHTML = nil
        }
        let spillsText = item.textFileName == nil && item.text?.isEmpty == false
            && (item.type == .text || item.type == .richText || item.type == .link)
        if spillsText, let text = item.text, let name = storeBlob(Data(text.utf8), ext: "txt") {
            item.textFileName = name
            item.text = nil
        }
    }

    @discardableResult
    private func spillPendingRichText() -> Bool {
        var spilled = false
        for index in items.indices where items[index].pendingRTF != nil
            || items[index].pendingHTML != nil
            || (items[index].textFileName == nil && items[index].text?.isEmpty == false
                && (items[index].type == .text || items[index].type == .richText || items[index].type == .link)) {
            spill(&items[index])
            spilled = true
        }
        return spilled
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var items: [ClipItem]
        var pinboards: [Pinboard]
        /// Ids deleted on the Mac that wrote the file, with when. Absent in
        /// files from earlier builds.
        var deleted: [String: Date]

        init(items: [ClipItem], pinboards: [Pinboard], deleted: [String: Date]) {
            self.items = items
            self.pinboards = pinboards
            self.deleted = deleted
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            items = try c.decode([ClipItem].self, forKey: .items)
            pinboards = try c.decode([Pinboard].self, forKey: .pinboards)
            deleted = try c.decodeIfPresent([String: Date].self, forKey: .deleted) ?? [:]
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }
        let data: Data
        do {
            data = try Data(contentsOf: storeURL)
        } catch {
            // The file is there but cannot be read - an iCloud Drive folder
            // still downloading, a permission problem. History is unknown, so
            // nothing may overwrite it.
            storeIsReadOnly = true
            launchNotice = L("Couldn't read your clipboard history. Nothing will be saved until Pesty is relaunched.")
            return
        }
        let snap: Snapshot
        do {
            snap = try JSONDecoder().decode(Snapshot.self, from: data)
        } catch {
            // Readable bytes that are not this app's format. Keep them under a
            // new name: writing an empty store over them is how a damaged file
            // turns into a lost history.
            guard let name = Self.quarantine(storeAt: storeURL) else {
                storeIsReadOnly = true
                launchNotice = L("Couldn't read your clipboard history. Nothing will be saved until Pesty is relaunched.")
                return
            }
            launchNotice = L("Your clipboard history was unreadable and has been set aside as %@.", name)
            return
        }
        items = snap.items
        pinboards = snap.pinboards
        tombstones = snap.deleted
        // Boards used to be created in one fixed blue that predates the
        // palette. Moving them onto the palette's blue keeps every board
        // showing a selected swatch, and the two are close enough that no board
        // visibly changes color.
        for i in pinboards.indices where pinboards[i].colorHex.uppercased() == "#5B8DEF" {
            pinboards[i].colorHex = "#007AFF"
        }
        items.sort { $0.createdAt > $1.createdAt }
        Self.unpinOrphanedClips(&items, boards: pinboards)
        if spillPendingRichText() { saveNow() }
        selectFirst()

        let live = liveFileNames()
        let directories = [blobsDir, imagesDir]
        saveQueue.async {
            Self.pruneOrphans(in: directories, live: live, modifiedBefore: Date().addingTimeInterval(-3600))
        }
    }

    /// Moves an undecodable store aside so the next save cannot overwrite it.
    nonisolated static func quarantine(storeAt url: URL) -> String? {
        let name = "store.corrupt-\(Int(Date().timeIntervalSince1970)).json"
        let target = url.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: url, to: target)
            return name
        } catch {
            return nil
        }
    }

    /// A clip pointing at a board that no longer exists would be invisible in
    /// both views; fall it back to history instead.
    private static func unpinOrphanedClips(_ clips: inout [ClipItem], boards: [Pinboard]) {
        let boardIDs = Set(boards.map(\.id))
        for i in clips.indices where clips[i].list.map({ !boardIDs.contains($0) }) == true {
            clips[i].list = nil
            clips[i].pinnedAt = nil
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveInBackground() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// The debounced save: encodes and writes off the main thread.
    private func saveInBackground() {
        saveWorkItem = nil
        guard !storeIsReadOnly else { return }
        let snapshot = Snapshot(items: items, pinboards: pinboards, deleted: tombstones)
        let url = storeURL
        saveQueue.async {
            Self.write(snapshot, to: url)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .pestyStoreDidSave, object: nil)
            }
        }
    }

    /// Writes before returning, for the moments the file has to be on disk
    /// when the call ends: quitting, and the merges that hand a result to the
    /// other Mac. It goes through the same serial queue, so a background save
    /// already under way cannot land after this one.
    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        guard !storeIsReadOnly else { return }
        let snapshot = Snapshot(items: items, pinboards: pinboards, deleted: tombstones)
        let url = storeURL
        saveQueue.sync { Self.write(snapshot, to: url) }
        NotificationCenter.default.post(name: .pestyStoreDidSave, object: nil)
    }

    private nonisolated static func write(_ snapshot: Snapshot, to url: URL) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        lastWritten.withLock { $0 = data }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: - Remote (CloudKit) apply

    /// Applies decoded CloudKit clips. The record's `container` field carries
    /// the pin: `history` for a clip that is only in history, a pinboard UUID
    /// for one that is also on that board. That is exactly `ClipItem.list`.
    func applyRemote(clips: [(ClipItem, container: String, imageSourceURL: URL?)]) {
        guard !clips.isEmpty else { return }
        for entry in clips {
            var item = entry.0
            // The per-app exclusion list is local to each Mac and is not synced, so a
            // clip from an ignored app copied on another device would otherwise arrive
            // here and land in history anyway. A privacy filter that leaks across
            // devices is not a privacy filter.
            guard !Settings.shared.isIgnoringSourceApp(item.sourceBundleID) else { continue }
            if let src = entry.imageSourceURL, let name = item.imageFileName {
                let dst = imagesDir.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: dst)
                try? FileManager.default.copyItem(at: src, to: dst)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dst.path)
            }
            if entry.container == "history" {
                item.list = nil
            } else if let boardID = UUID(uuidString: entry.container) {
                if !pinboards.contains(where: { $0.id == boardID }) {
                    pinboards.append(Pinboard(id: boardID, name: "Pinboard"))
                }
                item.list = boardID
            } else {
                continue
            }
            applyRemoteClip(item)
        }
        trimHistory()
        spillPendingRichText()
        if selectedID == nil { selectFirst() }
        reconcileMultiSelection()
        scheduleSave()
    }

    func applyRemoteDeletes(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let set = Set(ids)
        let removed = items.filter { set.contains($0.id) }
        items.removeAll { set.contains($0.id) }
        pinboards.removeAll { set.contains($0.id) }
        if case .pinboard(let cur) = source, set.contains(cur) { source = .history }
        // Clips on a board that just disappeared go back to history rather than
        // vanishing with it.
        for index in items.indices where items[index].list.map({ set.contains($0) }) == true {
            items[index].list = nil
            items[index].pinnedAt = nil
        }
        releaseFiles(of: removed)
        if let sel = selectedID, set.contains(sel) { selectFirst() }
        reconcileMultiSelection()
        scheduleSave()
    }

    /// Upserts pinboard name/color only; item membership syncs through clip records.
    func applyRemote(pinboards boards: [Pinboard]) {
        guard !boards.isEmpty else { return }
        for b in boards {
            if let i = pinboards.firstIndex(where: { $0.id == b.id }) {
                pinboards[i].name = b.name
                pinboards[i].colorHex = b.colorHex
            } else {
                pinboards.append(Pinboard(id: b.id, name: b.name, colorHex: b.colorHex))
            }
        }
        scheduleSave()
    }

    private func applyRemoteClip(_ item: ClipItem) {
        let replaced = items.filter { $0.id == item.id }
        items.removeAll { $0.id == item.id }
        // Content is unique across the whole table, not per container, so a
        // remote copy of something already held has to collapse into one
        // record - whichever copy is newer wins.
        if let dupIdx = duplicateIndex(of: item) {
            let dup = items[dupIdx]
            if dup.createdAt >= item.createdAt {
                releaseFiles(of: [item] + replaced)
                return
            }
            items.remove(at: dupIdx)
            releaseFiles(of: [dup])
        }
        var incoming = item
        spill(&incoming)
        items.insert(incoming, at: Self.historyInsertionIndex(for: incoming, in: items))
        retentionPrunedRecordNames.remove(item.id.uuidString)
        // Same-id replace: drop the old files unless something still uses them.
        releaseFiles(of: replaced)
    }

    func setICloudSync(_ enabled: Bool) {
        stopWatching()
        let target = (enabled ? ClipboardStore.iCloudBase : ClipboardStore.localBase) ?? ClipboardStore.localBase
        let newImages = target.appendingPathComponent("images", isDirectory: true)
        let newBlobs = target.appendingPathComponent("blobs", isDirectory: true)
        let newStore = target.appendingPathComponent("store.json")
        let fm = FileManager.default
        try? fm.createDirectory(at: newImages, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try? fm.createDirectory(at: newBlobs, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])

        copyFiles(from: imagesDir, to: newImages, extensions: ["png"])
        copyFiles(from: blobsDir, to: newBlobs, extensions: ["rtf", "html", "txt"])
        baseDir = target; imagesDir = newImages; blobsDir = newBlobs; storeURL = newStore

        // A store already in the target folder came from another Mac or an
        // earlier session: merge it rather than overwrite it.
        if let data = try? Data(contentsOf: newStore),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            mergeExternal(snap)
        } else {
            saveNow()
        }
        prepareDirectories()
        if enabled { startWatching() }
    }

    private func copyFiles(from src: URL, to dst: URL, extensions: Set<String>) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil) else { return }
        for file in files where extensions.contains(file.pathExtension) {
            let target = dst.appendingPathComponent(file.lastPathComponent)
            if !fm.fileExists(atPath: target.path) { try? fm.copyItem(at: file, to: target) }
        }
    }

    /// One clip per copied thing, newest copy first.
    ///
    /// The merge is a union: a clip one side holds and the other does not is
    /// kept, because "absent" means "not seen here yet" far more often than
    /// "deleted". A tombstone is the one thing that means deleted, and it only
    /// counts against a clip the shared file no longer lists - so an undo, or
    /// a re-copy of the same thing, revives the clip on every Mac.
    ///
    /// ponytail: a Mac saving state from before a deletion can revive the
    /// clip. A per-Mac revision counter would order those writes; the union
    /// keeps the data rather than lose it.
    nonisolated static func mergeClips(local: [ClipItem],
                                       remote: [ClipItem],
                                       tombstones: [String: Date]) -> [ClipItem] {
        let remoteIDs = Set(remote.map(\.id))
        // Newest first; on a tie the local copy comes first and wins below.
        let ordered = (local + remote).enumerated().sorted { lhs, rhs in
            lhs.element.createdAt == rhs.element.createdAt
                ? lhs.offset < rhs.offset
                : lhs.element.createdAt > rhs.element.createdAt
        }
        var ids = Set<UUID>()
        var hashes = Set<UInt64>()
        var merged: [ClipItem] = []
        for (_, clip) in ordered {
            if tombstones[clip.id.uuidString] != nil, !remoteIDs.contains(clip.id) { continue }
            guard ids.insert(clip.id).inserted, hashes.insert(clip.contentHash).inserted else { continue }
            merged.append(clip)
        }
        return merged
    }

    private func mergeExternal(_ snap: Snapshot) {
        let mergedTombstones = tombstones.merging(snap.deleted) { max($0, $1) }
        let remoteBoardIDs = Set(snap.pinboards.map(\.id))
        var boards = pinboards.filter { board in
            mergedTombstones[board.id.uuidString] == nil || remoteBoardIDs.contains(board.id)
        }
        for board in snap.pinboards where !boards.contains(where: { $0.id == board.id }) {
            boards.append(board)
        }
        var clips = Self.mergeClips(local: items, remote: snap.items, tombstones: mergedTombstones)
        Self.unpinOrphanedClips(&clips, boards: boards)

        // Nothing new: do not write, or two Macs answer each other's saves
        // forever.
        guard clips != items || boards != pinboards || mergedTombstones != tombstones else { return }
        items = clips
        pinboards = boards
        tombstones = mergedTombstones
        if case .pinboard(let current) = source, !boards.contains(where: { $0.id == current }) {
            source = .history
        }
        trimHistory()
        spillPendingRichText()
        if selectedItem == nil { selectFirst() }
        reconcileMultiSelection()
        saveNow()
    }

    private func recordTombstones(_ ids: some Sequence<UUID>, at date: Date = Date()) {
        for id in ids { tombstones[id.uuidString] = date }
        let cutoff = date.addingTimeInterval(-Self.tombstoneRetention)
        tombstones = tombstones.filter { $0.value >= cutoff }
    }

    private func startWatching() {
        stopWatching()
        let fd = open(storeURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            // Saves are atomic, so every event - the other Mac's and this
            // app's own - leaves the descriptor on a replaced file. Re-arm
            // first: returning early used to leave the watch dead for the rest
            // of the session.
            self.startWatching()
            guard let data = try? Data(contentsOf: self.storeURL) else { return }
            // This app's own save lands here too. Comparing bytes is a memcmp;
            // decoding is not, and merging our own file back in would answer
            // the other Mac's saves with saves of our own.
            if data == Self.lastWritten.withLock({ $0 }) { return }
            guard let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
            self.mergeExternal(snap)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileWatch = src
    }

    private func stopWatching() {
        fileWatch?.cancel()
        fileWatch = nil
    }
}
