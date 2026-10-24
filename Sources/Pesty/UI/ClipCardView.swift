import AppKit
import ImageIO
import SwiftUI

struct ClipCardView: View {
    let item: ClipItem
    let index: Int
    let selected: Bool
    /// Square side in points, handed down by the strip so every card grows and
    /// shrinks with the bar the same way Paste's do.
    let side: CGFloat

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
    private var bandColor: Color {
        Color(nsColor: AppIconProvider.dominantColor(forBundleID: item.sourceBundleID))
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
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        .scaleEffect(hovering && !selected ? 1.02 : 1.0)
        .zIndex(selected ? 1 : 0)
        // Selection has to land on the click, not drift in: a 0.32 s spring
        // made the ring fade up over half a second, which reads as the bar
        // being slow to acknowledge a click.
        .animation(.easeOut(duration: 0.1), value: selected)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Double-click pastes, single click selects. The single tap has to stay a
        // plain tap gesture behind the double-click one: selecting on the first
        // click would let `scrollToSelected` slide the card out from under the
        // second click, and the double-click would never complete.
        .onTapGesture(count: 2) { AppController.shared.pasteItem(item) }
        .onTapGesture { store.select(item.id) }
        .highPriorityGesture(TapGesture().modifiers(.shift).onEnded { store.extendSelection(to: item.id) })
        .highPriorityGesture(TapGesture().modifiers(.command).onEnded { store.toggleSelection(item.id) })
        .onDrag { ClipDragProvider.make(for: item) }
        .contextMenu { menu }
        .task(id: item.id) { await loadPreview() }
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
                    Text(item.createdAt.clipRelativeLong)
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
        preview = ClipPreviewProvider.cachedImage(for: item)
        fileInfo = nil
        previewFailed = false
        if ClipPreviewProvider.showsImage(item) {
            if preview == nil {
                preview = await ClipPreviewProvider.image(for: item, scale: NSScreen.main?.backingScaleFactor ?? 2)
            }
            guard preview == nil, item.type == .file else { return }
            previewFailed = true
        }
        guard item.type == .file else { return }
        fileInfo = await ClipPreviewProvider.fileInfo(for: item)
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
            // while the pointer is over the card.
            if index < 9 {
                HStack(spacing: 3) {
                    Spacer(minLength: 0)
                    Text(settings.quickPasteModifierDisplay)
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(index + 1)")
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

    private var metaLeft: String {
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

/// Reads an image clip's pixel dimensions from the file's metadata instead of
/// decoding it, and remembers them: the card footer asks on every render.
@MainActor
enum ImagePixelSize {
    private static var cache: [String: CGSize?] = [:]
    private static let cacheLimit = 512

    static func of(_ item: ClipItem) -> CGSize? {
        guard item.imageFileName != nil,
              let url = ClipboardStore.shared.imageURL(for: item) else { return nil }
        return of(url)
    }

    static func of(_ url: URL) -> CGSize? {
        let name = url.path
        if let cached = cache[name] { return cached }
        if cache.count >= cacheLimit { cache.removeAll() }
        let size = read(url)
        cache.updateValue(size, forKey: name)
        return size
    }

    private static func read(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: width, height: height)
    }
}
