import AppKit
import ImageIO
import SwiftUI

struct ClipCardView: View {
    let item: ClipItem
    /// Square side in points, handed down by the strip so every card grows and
    /// shrinks with the bar the same way Paste's do.
    let side: CGFloat

    /// Read from the store rather than passed in by the strip: the strip's own
    /// body then stays out of the selection path, and only the card whose flag
    /// flipped invalidates.
    private var selected: Bool { store.isSelected(item.id) }
    private var index: Int { store.visibleIndex(of: item.id) }

    @State private var hovering = false
    @State private var preview: NSImage?
    @State private var previewFailed = false
    @State private var fileInfo: ClipPreviewProvider.FileInfo?
    private var store: ClipboardStore { ClipboardStore.shared }
    private var settings: Settings { Settings.shared }

    private var bandHeight: CGFloat {
        max(Theme.bandMinHeight, side * Theme.bandHeightRatio)
    }

    /// The card's own color: the dominant color of the app the clip came from,
    /// which is what makes Paste's strip read as a row of colored cards.
    ///
    /// Resolved once per card instead of inside the body: a body evaluation
    /// happens on hover, on selection, and on every scroll-driven size pass,
    /// and this lookup is a cache probe whose miss rasterizes a whole icon.
    @State private var bandColor = Color(nsColor: AppIconProvider.neutral)

    /// "⌘3"-style label for the first nine visible cards, otherwise nil.
    private var quickPasteHint: String? {
        let position = index
        guard position < 9 else { return nil }
        return "\(position + 1)"
    }

    var body: some View {
        VStack(spacing: 0) {
            band
            contentArea
        }
        .frame(width: side, height: side)
        .background(Theme.cardBody)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        .background {
            // Paste's selection is a capsule behind the card, not a halo: the
            // card sits inside 4 pt of accent color.
            if selected {
                RoundedRectangle(
                    cornerRadius: Theme.cardCorner + Theme.selectedCardRing,
                    style: .continuous
                )
                .fill(Theme.selection)
                .padding(-Theme.selectedCardRing)
            }
        }
        // The drop shadow belongs to a plain opaque shape, not to the card
        // itself. Blurring the card means an offscreen pass over its text,
        // image, band and ring for every card on screen; a filled rounded
        // rectangle is something Core Animation can cache. The silhouette is
        // the same either way: the card's own rounded rect when idle, and the
        // ring's outer rect when selected, which is exactly the card grown by
        // the ring's width with the matching corner radius.
        .background {
            RoundedRectangle(
                cornerRadius: Theme.cardCorner + (selected ? Theme.selectedCardRing : 0),
                style: .continuous
            )
            .fill(Theme.cardBody)
            .padding(selected ? -Theme.selectedCardRing : 0)
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        }
        // Hover used to drive `scaleEffect` on the whole card. That makes a
        // 2 % scale a layout-affecting transform on a container whose shadow,
        // clipped image and text all have to be re-rasterized — the single
        // most expensive thing that happens while the pointer crosses the
        // strip. Drawn on a fixed-size shape it stays a Core Animation-only
        // change, and the card geometry never moves.
        .background {
            if hovering && !selected {
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .stroke(Theme.selection.opacity(0.55), lineWidth: 1.5)
                    .padding(-1.5)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .zIndex(selected ? 1 : 0)
        // Selection has to land on the click, not drift in: a 0.32 s spring
        // made the ring fade up over half a second, which reads as the bar
        // being slow to acknowledge a click.
        .animation(.easeOut(duration: 0.1), value: selected)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Click selects immediately, double-click pastes.
        //
        // The stacked `onTapGesture` pair this replaces made a single click wait
        // out the double-click interval before it fired: SwiftUI cannot tell a
        // single tap from the first half of a double tap until the second click
        // does not arrive, so selection landed ~0.25 s after the mouse came up.
        // That delay is what reads as "the card reacts a moment later".
        //
        // Selecting on the first click and pasting on the second removes the
        // wait entirely. The comment that used to justify the stacking warned
        // that selecting early would let the strip scroll the card out from
        // under the second click; that is no longer possible, because the strip
        // only scrolls when the selection is off screen, and a card you just
        // clicked is by definition on screen.
        .simultaneousGesture(
            TapGesture().modifiers(.shift).onEnded { store.extendSelection(to: item.id) }
        )
        .simultaneousGesture(
            TapGesture().modifiers(.command).onEnded { store.toggleSelection(item.id) }
        )
        // Clicks are routed by `BarPanel.sendEvent` — see `BarClickRouter`. A
        // tap gesture cannot be used for the plain click here: pairing it with
        // `onTapGesture(count: 2)` forces every single click to wait out the
        // system double-click interval before it is recognised, which measured
        // as a 350 ms gap between mouse-up and the selection landing.
        .onDrag { ClipDragProvider.make(for: item) }
        .contextMenu { menu }
        .task(id: item.id) { await loadPreview() }
        .onAppear { resolveBandColor() }
        .onChange(of: item.sourceBundleID) { _, _ in resolveBandColor() }
    }

    /// The colored header band: the clip's type and when it was copied on the
    /// left, the source app's own icon filling the band's right end and clipped
    /// by the card's corner, exactly as Paste draws it.
    private var band: some View {
        ZStack(alignment: .topLeading) {
            bandColor
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(cardTypeLabel)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.bandTextPrimary)
                    Text(item.cachedRelativeDate)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.bandTextSecondary)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
            }
            .padding(.leading, Theme.cardOverlayInset)
            // The icon owns the band's right end, so the labels stop short of it.
            .padding(.trailing, bandHeight + 6)
            .padding(.top, 9)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Image(nsImage: AppIconProvider.icon(forBundleID: item.sourceBundleID))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: bandHeight, height: bandHeight)
            }
        }
        .frame(height: bandHeight)
        .clipped()
    }

    private var cardTypeLabel: String {
        if item.type == .file, item.fileURLs.count > 1 {
            return L("%ld files", item.fileURLs.count)
        }
        return item.type.label
    }

    /// Everything below the band: the preview fills it, and the metadata line
    /// sits centered along the card's bottom edge.
    private var contentArea: some View {
        ZStack(alignment: .bottom) {
            content
            footer
                .padding(.horizontal, Theme.cardOverlayInset)
                .padding(.bottom, 10)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.cardBody)
        .clipped()
    }

    /// Image clips, and file clips pointing at an image, which is how a copied
    /// screenshot usually arrives, run edge to edge instead of sitting inset.
    private var showsImage: Bool {
        ClipPreviewProvider.showsImage(item) && !previewFailed
    }

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .image:
            imageCanvas
        case .color:
            ZStack {
                Rectangle().fill(Color(hex: item.colorHex ?? "#000") ?? .black)
                Text(item.colorHex ?? "")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white).shadow(radius: 1)
            }
        case .file:
            if showsImage {
                imageCanvas
            } else {
                fileContent
            }
        case .link:
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                Image(systemName: "safari").font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.cardTextSecondary)
                Text(item.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.cardTextPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        default:
            // The floating header reserves the top of the card, the metadata
            // the bottom; the text lives between them.
            Text(item.text ?? "")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.cardTextPrimary)
                .lineLimit(10)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 13)
                .padding(.top, Theme.cardContentTopInset)
                .padding(.bottom, Theme.cardContentBottomInset)
        }
    }

    /// Over a checkerboard, so a transparent cut-out is distinguishable from
    /// an image on the card surface.
    private var imageCanvas: some View {
        ZStack {
            CheckerboardBackground()
            if let image = preview ?? ClipPreviewProvider.cachedImage(for: item) {
                Image(nsImage: image)
                    .resizable().interpolation(.medium).scaledToFit()
            } else {
                placeholder("photo")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var fileContent: some View {
        VStack(spacing: 9) {
            Spacer(minLength: 0)
            if let icon = fileInfo?.icon ?? ClipPreviewProvider.cachedIcon(for: item) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: Theme.fileIconSize, height: Theme.fileIconSize)
                    .opacity(fileInfo?.isMissing == true ? 0.5 : 1)
            } else {
                Image(systemName: "doc.fill").font(.system(size: 32))
                    .foregroundStyle(Theme.cardTextTertiary)
            }
            Text(item.displayTitle).font(.system(size: 12))
                .foregroundStyle(Theme.cardTextSecondary).lineLimit(2)
                .multilineTextAlignment(.center)
            if fileInfo?.isMissing == true {
                Text(L("File not found"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.cardTextTertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 13)
        .padding(.top, Theme.cardContentTopInset)
        .padding(.bottom, Theme.cardContentBottomInset)
    }

    private func loadPreview() async {
        // Both lookups hand back what is already cached before they suspend,
        // so a card that scrolls back into view comes up on the same run loop
        // pass instead of showing an empty frame and then filling in — the
        // flash that made the strip look like it was stuttering while it
        // scrolled.
        preview = ClipPreviewProvider.cachedImage(for: item)
        if preview == nil, ClipPreviewProvider.showsImage(item) {
            preview = ClipPreviewProvider.synchronouslyLoadableImage(for: item)
        }
        fileInfo = ClipPreviewProvider.cachedFileInfo(for: item)
        previewFailed = false

        if ClipPreviewProvider.showsImage(item) {
            if preview == nil {
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                preview = await ClipPreviewProvider.image(for: item, scale: scale)
            }
            guard preview == nil, item.type == .file else { return }
            previewFailed = true
        }
        guard item.type == .file, fileInfo == nil else { return }
        fileInfo = await ClipPreviewProvider.fileInfo(for: item)
    }

    private func resolveBandColor() {
        bandColor = Color(nsColor: AppIconProvider.dominantColor(forBundleID: item.sourceBundleID))
    }

    private func placeholder(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 30))
            .foregroundStyle(Theme.cardTextTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        ZStack {
            Text(metaLeft)
                .font(.system(size: 11))
                .foregroundStyle(Theme.cardTextSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .shadow(color: Theme.overlayTextShadow, radius: 2, y: 1)
                .frame(maxWidth: .infinity)
            // Paste keeps cards clean, so the quick-paste hint only shows
            // while the pointer is over the card. Its text is built once at
            // card creation instead of on every hover and scroll pass, which
            // is when this footer re-renders.
            if let quickPasteHint {
                HStack(spacing: 3) {
                    Spacer(minLength: 0)
                    Text(settings.quickPasteModifierDisplay)
                        .font(.system(size: 10, weight: .semibold))
                    Text(quickPasteHint)
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Theme.cardTextTertiary)
                .opacity(hovering ? 1 : 0)
            }
        }
    }

    private var isSingleImageFile: Bool {
        ClipPreviewProvider.imageFileURL(for: item) != nil
    }

    /// NSHomeDirectory is the sandbox container in the App Store build, so the
    /// real home comes from the account record instead.
    private static let homePath: String = {
        if let home = getpwuid(getuid())?.pointee.pw_dir { return String(cString: home) }
        return NSHomeDirectory()
    }()

    private static func abbreviatedPath(_ path: String) -> String {
        if path == homePath { return "~" }
        guard path.hasPrefix(homePath + "/") else { return path }
        return "~" + path.dropFirst(homePath.count)
    }

    /// The footer line is a pure function of the clip, and the strip re-renders
    /// a card on hover, on selection, and on every scroll pass. Resolving it
    /// once per clip keeps `ImagePixelSize` and the URL parsing off that path.
    private var metaLeft: String {
        ClipCardMetaCache.value(for: item) { computeMetaLeft() }
    }

    private func computeMetaLeft() -> String {
        switch item.type {
        case .text, .richText:
            return L("%ld characters", item.charCount)
        case .link:
            return (item.text ?? "").replacingOccurrences(of: "https://", with: "")
                                    .replacingOccurrences(of: "http://", with: "")
        case .file:
            guard item.fileURLs.count == 1,
                  let url = item.fileURLs.first.flatMap(URL.init(string:)) else {
                return item.fileURLs
                    .compactMap { URL(string: $0)?.lastPathComponent }
                    .joined(separator: ", ")
            }
            // An image shows what it is, so its size is the useful fact; a
            // screenshot's path is a timestamped folder nobody reads. Files
            // without a preview get the full location instead, since two
            // documents of the same name differ only by where they live.
            if isSingleImageFile {
                guard let size = ImagePixelSize.of(url) else { return url.lastPathComponent }
                return "\(Int(size.width)) × \(Int(size.height))"
            }
            return Self.abbreviatedPath(url.path)
        case .image:
            guard let size = ImagePixelSize.of(item) else { return L("Image") }
            return "\(Int(size.width)) × \(Int(size.height))"
        case .color:
            return item.colorHex ?? L("Color")
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button { AppController.shared.pasteItem(item) } label: {
            Label(AppController.shared.pasteMenuTitle, systemImage: "doc.on.clipboard")
        }

        Button { AppController.shared.pasteItem(item, format: .plainText) } label: {
            Label(L("Paste as Plain Text"), systemImage: "text.alignleft")
        }
        .disabled(item.plainText == nil)

        Button { AppController.shared.pasteItem(item, format: .cleanFormatting) } label: {
            Label(L("Paste with Clean Formatting"), systemImage: "paintbrush")
        }
        .disabled(!FormatConverter.canConvert(item))

        Button { AppController.shared.pasteItem(item, format: .markdown) } label: {
            Label(L("Paste as Markdown"), systemImage: "number")
        }
        .disabled(!FormatConverter.canConvert(item))

        Button { AppController.shared.copyItem(item) } label: {
            Label(L("Copy"), systemImage: "doc.on.doc")
        }

        Divider()

        Button { AppController.shared.editItem(item) } label: {
            Label(L("Edit"), systemImage: "pencil")
        }
        .disabled(!isEditable)

        if writingToolsAvailable {
            Button { AppController.shared.editItem(item, launchWritingTools: true) } label: {
                Label(L("Writing Tools"), systemImage: "pencil.and.scribble")
            }
        }

        Button { renameItem() } label: {
            Label(L("Rename…"), systemImage: "pencil.line")
        }

        Divider()

        Menu {
            if store.pinboards.isEmpty {
                Button(L("No Pinboards Yet")) {}
                    .disabled(true)
            } else {
                ForEach(store.pinboards) { b in
                    Button { store.saveToPinboard(item, boardID: b.id) } label: {
                        Label {
                            Text(b.name)
                        } icon: {
                            Image(nsImage: Self.pinboardMenuIcon(color: NSColor(b.color)))
                                .renderingMode(.original)
                        }
                    }
                }
            }
            Divider()
            Button { pinToNewBoard() } label: {
                Label(L("Create Pinboard…"), systemImage: "plus")
            }
        } label: {
            Label(L("Pin"), systemImage: "pin")
        }

        Divider()

        Button { AppController.shared.showPreview(for: item) } label: {
            Label(L("Preview"), systemImage: "eye")
        }

        Button { AppController.shared.showSharePicker(for: item) } label: {
            Label(L("Share"), systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive) {
            AppController.shared.deleteSelection(containing: item)
        } label: {
            Label(deleteMenuTitle, systemImage: "trash")
        }
    }

    private var deleteMenuTitle: String {
        let count = store.multiSelectedIDs.contains(item.id) ? store.multiSelectedIDs.count : 1
        return count > 1 ? L("Delete %ld Clips", count) : L("Delete")
    }

    private var isEditable: Bool {
        [.text, .richText, .link, .color].contains(item.type)
    }

    private var writingToolsAvailable: Bool {
        guard [.text, .richText, .link].contains(item.type) else { return false }
        guard #available(macOS 15.2, *) else { return false }
        return NSWritingToolsCoordinator.isWritingToolsAvailable
    }

    private func renameItem() {
        if let title = TextPrompt.run(title: L("Rename"), message: L("Card title"),
                                      defaultValue: item.customTitle ?? "") {
            store.setTitle(title, for: item)
        }
    }

    private func pinToNewBoard() {
        if let name = TextPrompt.run(title: L("Create Pinboard"), message: L("Name")) {
            let board = store.addPinboard(name: name)
            store.saveToPinboard(item, boardID: board.id)
        }
    }

    private static func pinboardMenuIcon(color: NSColor) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// The standard transparency checkerboard drawn behind image clips, in the
/// palette of the current appearance. A Canvas rather than a tiled image: the
/// pattern is a handful of rects, and this keeps it resolution independent
/// without shipping an asset.
private struct CheckerboardBackground: View {
    var square: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.checkerBase))
            let columns = Int(ceil(size.width / square))
            let rows = Int(ceil(size.height / square))
            for row in 0..<max(rows, 0) {
                for column in 0..<max(columns, 0) where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * square,
                                      y: CGFloat(row) * square,
                                      width: square,
                                      height: square)
                    context.fill(Path(rect), with: .color(Theme.checkerAlt))
                }
            }
        }
        .drawingGroup()
    }
}

/// Footer text per clip, keyed by the clip's identity and the two things it
/// reads from disk (image file name, file URLs). A rename or a re-copy stamps a
/// new `createdAt`, which is folded into the token so a promoted clip does not
/// keep the previous line.
@MainActor
enum ClipCardMetaCache {
    private struct Entry {
        let token: String
        let text: String
    }

    @MainActor private static var storage: [UUID: Entry] = [:]
    private static let limit = 1_024

    static func value(for item: ClipItem, compute: () -> String) -> String {
        let token = "\(item.createdAt.timeIntervalSince1970)|\(item.imageFileName ?? "")|\(item.fileURLs.joined(separator: "|"))|\(item.customTitle ?? "")|\(item.text?.count ?? -1)"
        if let entry = storage[item.id], entry.token == token { return entry.text }
        if storage.count >= limit { storage.removeAll(keepingCapacity: true) }
        let text = compute()
        storage[item.id] = Entry(token: token, text: text)
        return text
    }
}

/// Reads an image clip's pixel dimensions from the file's metadata instead of
/// decoding it, and remembers them: the card footer asks on every render.
@MainActor
enum ImagePixelSize {
    /// Guarded by the lock rather than the main actor: the read runs on a
    /// background queue, but the dictionary is still shared with the caller.
    nonisolated(unsafe) private static var cache: [String: CGSize?] = [:]
    nonisolated private static let cacheLimit = 512
    nonisolated private static let lock = NSLock()

    static func of(_ item: ClipItem) -> CGSize? {
        guard item.imageFileName != nil,
              let url = ClipboardStore.shared.imageURL(for: item) else { return nil }
        return of(url)
    }

    /// Nonisolated so the header read runs off the main actor: a missing or
    /// network-backed file used to stall the strip for a full main-thread turn
    /// the first time a card appeared.
    nonisolated static func of(_ url: URL) -> CGSize? {
        let name = url.path
        lock.lock()
        if let cached = cache[name] { lock.unlock(); return cached }
        lock.unlock()
        let size = read(url)
        lock.lock()
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache.updateValue(size, forKey: name)
        lock.unlock()
        return size
    }

    nonisolated private static func read(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: width, height: height)
    }
}
