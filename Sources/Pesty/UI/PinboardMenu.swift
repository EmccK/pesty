import AppKit
import SwiftUI

// MARK: - Swatches

/// The small circle a board's color shows up as inside ordinary menu items and
/// in the tab row.
enum PinboardSwatch {
    static func dot(hex: String, size: CGFloat = 12) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            (NSColor(hex: hex) ?? .systemGray).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

// MARK: - Menu

/// Retains the closure a menu item fires. `NSMenuItem` does not keep its
/// target alive, so the item holds this object in `representedObject`.
private final class MenuAction: NSObject {
    private let run: () -> Void

    init(_ run: @escaping () -> Void) {
        self.run = run
    }

    @objc func fire() {
        run()
    }
}

@MainActor
enum PinboardMenuBuilder {
    static func menu(for board: Pinboard,
                     rename: @escaping () -> Void,
                     delete: @escaping () -> Void,
                     recolor: @escaping (String) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(action(L("Rename…"), symbol: "pencil", run: rename))
        menu.addItem(action(L("Delete Pinboard"), symbol: "trash", run: delete))
        menu.addItem(.separator())

        // Paste puts the color row at the foot of this menu rather than in a
        // submenu: the colors are the point of the menu, and a submenu hides
        // them behind a second click.
        let swatches = NSMenuItem()
        swatches.view = SwatchRowView(selectedHex: board.colorHex, onPick: recolor)
        menu.addItem(swatches)
        return menu
    }

    private static func action(_ title: String, symbol: String, run: @escaping () -> Void) -> NSMenuItem {
        let handler = MenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
        item.target = handler
        item.representedObject = handler
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }
}

/// The row of color circles a board's context menu carries.
///
/// Drawn and hit-tested by hand rather than built from `NSButton`s: a menu item
/// view sits inside the menu's own tracking loop, where a button's tracking
/// fights the menu's for the mouse. Here the whole row is one view, and a click
/// is resolved by which circle it landed on.
private final class SwatchRowView: NSView {
    private let onPick: (String) -> Void
    private let colors = Pinboard.palette
    private let selectedIndex: Int?
    private let cell: CGFloat = 24
    private let gap: CGFloat = 6
    private let inset: CGFloat = 12

    init(selectedHex: String?, onPick: @escaping (String) -> Void) {
        self.onPick = onPick
        self.selectedIndex = Pinboard.palette.firstIndex {
            $0.caseInsensitiveCompare(selectedHex ?? "") == .orderedSame
        }
        let width = CGFloat(colors.count) * cell + CGFloat(colors.count - 1) * gap + inset * 2
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: cell + 16))
        setAccessibilityLabel(L("Color"))
        setAccessibilityRole(.colorWell)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func centerX(of index: Int) -> CGFloat {
        inset + CGFloat(index) * (cell + gap) + cell / 2
    }

    override func draw(_ dirtyRect: NSRect) {
        for (index, hex) in colors.enumerated() {
            guard let color = NSColor(hex: hex) else { continue }
            let selected = index == selectedIndex
            let mid = centerX(of: index)
            let y = bounds.midY
            color.setFill()
            let diameter: CGFloat = selected ? 13 : 19
            NSBezierPath(ovalIn: NSRect(x: mid - diameter / 2, y: y - diameter / 2,
                                        width: diameter, height: diameter)).fill()
            if selected {
                color.setStroke()
                let ring = NSBezierPath(ovalIn: NSRect(x: mid - 10.5, y: y - 10.5, width: 21, height: 21))
                ring.lineWidth = 2.5
                ring.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = colors.indices.first(where: { abs(centerX(of: $0) - point.x) <= cell / 2 }) else {
            return
        }
        onPick(colors[index])
        // A view-backed item does not close the menu by itself.
        enclosingMenuItem?.menu?.cancelTracking()
    }
}

// MARK: - Right click

/// Hands right-clicks on a SwiftUI view to a native `NSMenu`.
///
/// SwiftUI's `.contextMenu` cannot carry the swatch row - it has no way to put
/// an arbitrary view in a menu - and it has no right-click gesture to fall back
/// on. So the tab wears this invisible view, which claims the hit only while a
/// right-click is in flight and steps out of the way for everything else, and
/// pops the menu itself.
struct PinboardMenuHost: NSViewRepresentable {
    let board: Pinboard
    var onRename: () -> Void
    var onDelete: () -> Void
    var onColor: (String) -> Void

    func makeNSView(context: Context) -> RightClickView {
        let view = RightClickView()
        view.build = { menu() }
        return view
    }

    func updateNSView(_ view: RightClickView, context: Context) {
        view.build = { menu() }
    }

    private func menu() -> NSMenu {
        PinboardMenuBuilder.menu(for: board, rename: onRename, delete: onDelete, recolor: onColor)
    }
}

final class RightClickView: NSView {
    var build: (() -> NSMenu)?

    /// Only a right-click belongs to this view. Left clicks, drags and cursor
    /// updates fall through to the SwiftUI tab underneath, which still has to
    /// select and hover normally.
    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return super.hitTest(point)
        default:
            return nil
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = build?() else { return }
        // The menu is its own window; without this the bar reads the focus
        // change as the pointer having left and hides itself mid-menu.
        let controller = AppController.shared
        let previous = controller.suppressAutoHide
        controller.suppressAutoHide = true
        NSMenu.popUpContextMenu(menu, with: event, for: self)
        controller.suppressAutoHide = previous
    }
}
