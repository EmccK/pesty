import AppKit
import UniformTypeIdentifiers

@MainActor
enum ClipDragProvider {
    private static let colorTypeIdentifier = "com.apple.cocoa.pasteboard.color"

    /// Stamped on every drag that starts inside the bar.
    ///
    /// The payload registrations below describe the *clip's content* — a PNG, a
    /// file URL, some text — which is what a drop outside Pesty needs. A drop
    /// target inside Pesty needs the opposite: which card is being dragged, so
    /// it can move that clip instead of importing a second copy of it. Without
    /// this identifier a drop target cannot tell one of our own cards from
    /// something dragged in from another app.
    static let clipType = UTType(exportedAs: "com.greycorelabs.pesty.clip")

    /// The clip being dragged out of the bar right now, if any.
    ///
    /// A drop target can read the clip's id from the provider, but only through
    /// a completion handler, and that handler lands well after the mouse comes
    /// up: 295-332 ms in measurements here, with the main thread idle the whole
    /// time. Pinning is a local, in-process move that should not wait on it, so
    /// the id is stamped at drag start and `PinboardDropTargetView` acts on the
    /// stamp instead. The provider registration stays as the fallback for a
    /// target that only speaks content types.
    private(set) static var draggedItemID: UUID?

    static func make(for item: ClipItem) -> NSItemProvider {
        draggedItemID = item.id
        let provider = NSItemProvider()
        register(Data(item.id.uuidString.utf8), as: clipType.identifier, on: provider)
        switch item.type {
        case .image:
            registerImage(item, on: provider)
        case .file:
            let urls = item.fileURLs.compactMap(URL.init(string:)).filter(\.isFileURL)
            if urls.count == 1, let url = urls.first {
                provider.registerObject(url as NSURL, visibility: .all)
                provider.suggestedName = url.lastPathComponent
            } else {
                registerText(item.text ?? item.displayTitle, on: provider)
            }
        case .link:
            if let text = ClipboardStore.shared.fullText(for: item), let url = URL(string: text) {
                provider.registerObject(url as NSURL, visibility: .all)
            }
            registerText(ClipboardStore.shared.fullText(for: item) ?? "", on: provider)
        case .color:
            if let hex = item.colorHex, let color = NSColor(hex: hex),
               let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) {
                register(data, as: colorTypeIdentifier, on: provider)
            }
            registerText(item.colorHex ?? "", on: provider)
        case .richText:
            if let rtf = ClipboardStore.shared.blobData(named: item.rtfFileName) {
                register(rtf, as: UTType.rtf.identifier, on: provider)
            }
            registerText(ClipboardStore.shared.fullText(for: item) ?? "", on: provider)
        case .text:
            registerText(ClipboardStore.shared.fullText(for: item) ?? "", on: provider)
        }
        if provider.suggestedName == nil { provider.suggestedName = item.displayTitle }
        return provider
    }

    /// Forgets the in-flight drag.
    ///
    /// Called once the drop has been served, when a drag session ends, and
    /// whenever the bar goes away, so a cancelled drag cannot leave a stale id
    /// behind for a later drop to act on.
    ///
    /// A stale stamp is not harmless: `PinboardDropTargetView.hitTest` reads it
    /// to decide whether the invisible overlay claims a mouse event, and that
    /// read never looks at the pasteboard. Left set, it would let the overlay
    /// hold the whole tab and swallow clicks. The hit test defends itself by
    /// also checking the event type, but clearing here is what keeps the
    /// stamp honest in the first place.
    static func clearDraggedItem() {
        draggedItemID = nil
    }

    private static func registerImage(_ item: ClipItem, on provider: NSItemProvider) {
        guard let url = ClipboardStore.shared.imageURL(for: item) else { return }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            do {
                completion(try Data(contentsOf: url), nil)
            } catch {
                completion(nil, error)
            }
            return nil
        }
        provider.suggestedName = "Pesty Image \(item.id.uuidString.prefix(8)).png"
    }

    private static func registerText(_ text: String, on provider: NSItemProvider) {
        register(Data(text.utf8), as: UTType.utf8PlainText.identifier, on: provider)
    }

    private static func register(_ data: Data, as identifier: String, on provider: NSItemProvider) {
        provider.registerDataRepresentation(forTypeIdentifier: identifier, visibility: .all) { completion in
            // Runs later, on whatever queue the drop target asks from - which is
            // exactly why no target inside Pesty reads it.
            completion(data, nil)
            return nil
        }
    }
}
