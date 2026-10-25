import SwiftUI

/// The bar's source switcher, shaped like Paste's own tab row.
///
/// Paste does not draw a segmented control or a colored selection: every source
/// is a dot-and-label item on a shared baseline, and the *current* one sits in a
/// plain light-gray capsule with the label at full text strength. The create
/// button is the last item in the same row and is drawn as a bare glyph, so the
/// whole row reads as one cluster rather than a control group.
struct PinboardTabs: View {
    @Bindable private var store = ClipboardStore.shared
    /// The source under the pointer. Paste quietly lifts an unselected label to
    /// full strength on hover; it never draws a hover capsule.
    @State private var hoveredID: UUID?
    @State private var addHovered = false

    /// True while the search field owns the row. Paste collapses its sources to
    /// bare dots in that state: `TabBar` carries a
    /// `pinboardViewTrailingConstraint` and a `labelsStackViewTrailingConstraint`
    /// that give the expanding field the room and drop every label to zero
    /// width, leaving only the colored dot (and `collapsedItemLimit` bounds how
    /// many dots stay visible). Reproduced here by hiding the labels rather than
    /// letting the field's `layoutPriority` squeeze them, which produced a row of
    /// stray dots with no relationship to the search state.
    var collapsed: Bool = false

    /// Stable identity for the history tab. Boards carry their own ids; the
    /// history source does not, so it needs a constant for hover tracking.
    private static let historyTabID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // Measured off Paste: adjacent capsules clear each other by ~6.5 pt.
            // The tabs carry their own horizontal padding, so this spacing is
            // the gap between the capsules themselves - at 2 pt they read as one
            // continuous strip instead of a row of separate items.
            HStack(spacing: collapsed ? 0 : 6) {
                tab(id: Self.historyTabID,
                    title: L("Clipboard History"),
                    dot: nil,
                    icon: "clock.arrow.circlepath",
                    selected: store.source == .history) {
                    select(.history)
                }

                ForEach(store.pinboards) { board in
                    tab(id: board.id,
                        title: board.name,
                        dot: board.color,
                        icon: nil,
                        selected: store.source == .pinboard(board.id)) {
                        select(.pinboard(board.id))
                    }
                    // Rename lived only in the context menu, which nobody found (#100).
                    .simultaneousGesture(TapGesture(count: 2).onEnded { rename(board) })
                    .help(L("Double-click or right-click to rename"))
                    // The menu is native so it can carry the color row Paste
                    // puts at its foot; see `PinboardMenuHost`. This plain
                    // context menu stays as the fallback for the case where the
                    // host view never sees the right-click - renaming and
                    // deleting a board must not depend on the color picker
                    // working.
                    .contextMenu {
                        Button(L("Rename…")) { rename(board) }
                        Button(L("Delete Pinboard"), role: .destructive) {
                            store.deletePinboard(board.id)
                        }
                    }
                    .overlay {
                        PinboardMenuHost(
                            board: board,
                            onRename: { rename(board) },
                            onDelete: { store.deletePinboard(board.id) },
                            onColor: { store.setPinboardColor($0, for: board.id) }
                        )
                    }
                }

                addButton
            }
            .fixedSize()
        }
        // The row is a cluster: it shrinks to its content and the caller
        // centers it, exactly like Paste centering its sources between the
        // search control and the overflow menu.
        .fixedSize(horizontal: true, vertical: false)
        .animation(.easeOut(duration: 0.18), value: collapsed)
    }

    private func tab(id: UUID,
                     title: String,
                     dot: Color?,
                     icon: String?,
                     selected: Bool,
                     action: @escaping () -> Void) -> some View {
        let hovered = hoveredID == id
        return Button(action: action) {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.chromeTextPrimary)
                }
                if let dot {
                    // Measured off Paste: 12 pt across, not a 7 pt bullet. The
                    // color is what the eye lands on when scanning the row, so
                    // it has to carry at least as much weight as the label.
                    Circle()
                        .fill(dot)
                        .frame(width: 12, height: 12)
                }
                if !collapsed {
                    Text(title)
                        .font(.system(size: 13, weight: .regular))
                        .lineLimit(1)
                        // Paste prints the running source at full strength and the
                        // rest at secondary; the capsule carries the selection, not
                        // the text color.
                        .foregroundStyle(selected || hovered
                                         ? Theme.chromeTextPrimary
                                         : Theme.chromeTextSecondary)
                        .transition(.opacity)
                }
            }
            // A collapsed tab keeps a tappable target around its dot instead of
            // shrinking to the 7 pt dot itself.
            .padding(.horizontal, collapsed ? 6 : 9)
            .frame(height: 28)
            .background {
                // Paste drops the selection capsule in the collapsed state:
                // with the labels gone a capsule would just be a large gray blob
                // around one dot. The running source is indicated by its position
                // in the row, not by the pill.
                //
                // While the row is open, hovering lifts a tab into a capsule of
                // its own - lighter than the selection, so the two never read as
                // the same state.
                if !collapsed && (selected || hovered) {
                    Capsule().fill(selected ? Theme.pillBG : Theme.pillHover)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { inside in
            if inside {
                hoveredID = id
            } else if hoveredID == id {
                hoveredID = nil
            }
        }
        // The capsule fades rather than popping: the pointer crosses a row of
        // tabs quickly, and a hard cut on each crossing reads as flicker.
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityLabel(collapsed ? title : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Bare "+" on the tab baseline. Paste draws no capsule behind it at rest.
    private var addButton: some View {
        Button(action: addPinboard) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(addHovered ? Theme.chromeTextPrimary : Theme.chromeTextSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { addHovered = $0 }
        .help(L("New Pinboard"))
        .accessibilityLabel(L("New Pinboard"))
    }

    /// Switches source and puts the row back to rest.
    ///
    /// The search collapses *after* the source change: doing it first would
    /// clear the query against the old board and run a second, immediately
    /// superseded selection pass, and it would also re-expand every label
    /// before the tab under the pointer had finished being clicked.
    private func select(_ source: BarSource) {
        store.source = source
        store.selectFirst()
        AppController.shared.collapseBarSearch()
    }

    private func addPinboard() {
        let board = store.addPinboard(name: L("New Pinboard"))
        select(.pinboard(board.id))
    }

    private func rename(_ board: Pinboard) {
        if let name = TextPrompt.run(title: L("Rename Pinboard"),
                                     message: L("Enter a new name"),
                                     defaultValue: board.name) {
            store.renamePinboard(board.id, to: name)
        }
    }
}

@MainActor
enum TextPrompt {
    static func run(title: String, message: String, defaultValue: String = "") -> String? {
        AppController.shared.suppressAutoHide = true
        defer { AppController.shared.suppressAutoHide = false }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L("OK"))
        alert.addButton(withTitle: L("Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let v = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }
}
