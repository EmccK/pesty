import AppKit
import Carbon.HIToolbox

/// How a clip's content is written to the pasteboard when pasting.
enum PasteFormat {
    /// The clip exactly as captured.
    case original
    /// Text only, all formatting removed.
    case plainText
    /// Bold, italic, underline, and links survive; fonts, sizes, and colors
    /// are normalized away.
    case cleanFormatting
    /// Rich content converted to Markdown text.
    case markdown
}

@MainActor
enum PasteService {
    private static let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")
    private static let packagedBundleID = "com.greycorelabs.pesty"

    private static func sourceString(for item: ClipItem) -> String {
        item.sourceBundleID ?? Bundle.main.bundleIdentifier ?? packagedBundleID
    }

    private static func markSource(of item: ClipItem, on pasteboard: NSPasteboard) {
        pasteboard.setString(sourceString(for: item), forType: sourceType)
    }

    @discardableResult
    static func copy(_ item: ClipItem,
                     format: PasteFormat = .original,
                     to pasteboard: NSPasteboard = .general) -> Int {
        switch format {
        case .plainText:
            if let text = item.plainText {
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                markSource(of: item, on: pasteboard)
                return pasteboard.changeCount
            }
        case .cleanFormatting:
            if let rtf = FormatConverter.cleanedRTF(for: item) {
                pasteboard.clearContents()
                pasteboard.setData(rtf, forType: .rtf)
                if let text = item.plainText { pasteboard.setString(text, forType: .string) }
                markSource(of: item, on: pasteboard)
                return pasteboard.changeCount
            }
            // No rich source to clean: plain text is the honest result.
            if item.plainText != nil {
                return copy(item, format: .plainText, to: pasteboard)
            }
        case .markdown:
            if let markdown = FormatConverter.markdown(for: item) {
                pasteboard.clearContents()
                pasteboard.setString(markdown, forType: .string)
                markSource(of: item, on: pasteboard)
                return pasteboard.changeCount
            }
            if item.plainText != nil {
                return copy(item, format: .plainText, to: pasteboard)
            }
        case .original:
            break
        }
        if item.type == .image {
            // Fast path: the stored PNG bytes go to the pasteboard as-is —
            // no decode, no TIFF re-encode — so pasting a big screenshot
            // doesn't stall the main thread while the bar animates away.
            // TIFF is still promised, but only as a lazy provider: apps that
            // take PNG (most of them) never pay for the encode, while the ones
            // that only read `public.tiff` still get their copy.
            if let url = ClipboardStore.shared.imageURL(for: item),
               let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setData(data, forType: .png)
                pasteboardItem.setString(sourceString(for: item), forType: sourceType)
                pasteboardItem.setDataProvider(LazyTIFFProvider(pngData: data),
                                               forTypes: [.tiff])
                pasteboard.clearContents()
                pasteboard.writeObjects([pasteboardItem])
                return pasteboard.changeCount
            }
            guard let img = ClipboardStore.shared.loadImage(for: item) else {
                return pasteboard.changeCount
            }
            pasteboard.clearContents()
            pasteboard.writeObjects([img])
            markSource(of: item, on: pasteboard)
            return pasteboard.changeCount
        }
        pasteboard.clearContents()
        switch item.type {
        case .image:
            break
        case .file:
            let urls = item.fileURLs.compactMap { URL(string: $0) }
            if !urls.isEmpty { pasteboard.writeObjects(urls as [NSURL]) }
            if let t = item.text { pasteboard.setString(t, forType: .string) }
        case .color:
            if let hex = item.colorHex, let c = NSColor(hex: hex) {
                pasteboard.writeObjects([c])
                pasteboard.setString(hex, forType: .string)
            }
        case .richText:
            if let rtf = item.rtfData { pasteboard.setData(rtf, forType: .rtf) }
            if let t = item.text { pasteboard.setString(t, forType: .string) }
        case .text, .link:
            if let t = item.text { pasteboard.setString(t, forType: .string) }
        }
        markSource(of: item, on: pasteboard)
        return pasteboard.changeCount
    }

    static func paste(_ item: ClipItem,
                      into targetApp: NSRunningApplication?,
                      monitor: ClipboardMonitor,
                      format: PasteFormat = .original) {
        // Decide up front, then activate the target BEFORE writing the
        // pasteboard so the app switch (100-300ms) overlaps the write
        // instead of stacking after it.
        var shouldActivate = false
        var shouldPasteKeystroke = false
        if let target = targetApp, !target.isTerminated {
            #if MAS
            // Mac App Store (sandboxed) build: copy the clip and return focus
            // to the app the user came from so they can paste with ⌘V. No
            // Accessibility APIs and no synthetic keystrokes are used.
            shouldActivate = true
            #else
            // Direct-download build: optionally paste straight into the active
            // app by synthesizing ⌘V. This requires the Accessibility grant.
            if Settings.shared.pasteDirectly {
                if AXIsProcessTrusted() {
                    shouldActivate = true
                    shouldPasteKeystroke = true
                } else {
                    AppController.shared.noteBlockedDirectPaste()
                }
            }
            #endif
        }
        if shouldActivate { targetApp?.activate() }

        let change = copy(item, format: format)
        monitor.suppressUntilChangeCount = change
        if Settings.shared.playSound { NSSound(named: "Pop")?.play() }

        if shouldPasteKeystroke, let target = targetApp {
            waitForFrontmost(target, attempts: 32)
        }
    }

    #if !MAS
    private static func waitForFrontmost(_ app: NSRunningApplication, attempts: Int) {
        guard attempts > 0, !app.isTerminated else { return }
        // One frame of cadence: fast enough to send ⌘V the moment the target
        // takes focus, slow enough not to spin the main queue.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { sendCommandV() }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
            waitForFrontmost(app, attempts: attempts - 1)
        }
    }

    private static func sendCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    @discardableResult
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
    #endif
}

/// Answers a `public.tiff` request from the stored PNG bytes, and only if the
/// receiving app actually asks for one.
///
/// `NSImage` on the pasteboard used to hand out TIFF and PNG alike, which meant
/// every paste paid for a full decode and TIFF encode even though almost every
/// app reads the PNG. Promising TIFF here keeps those apps working while
/// leaving the fast path free of the encode. `NSPasteboardItem` retains its
/// data provider for as long as the item lives on the pasteboard.
private final class LazyTIFFProvider: NSObject, NSPasteboardItemDataProvider {
    private let pngData: Data

    init(pngData: Data) {
        self.pngData = pngData
    }

    func pasteboard(_ pasteboard: NSPasteboard?,
                    item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff,
              let image = NSImage(data: pngData),
              let tiff = image.tiffRepresentation else { return }
        item.setData(tiff, forType: .tiff)
    }
}
