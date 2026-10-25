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

    /// Stable identity for the history tab. Boards carry their own ids; the
    /// history source does not, so it needs a constant for hover tracking.
    private static let historyTabID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                tab(id: Self.historyTabID,
                    title: L("Clipboard History"),
                    dot: nil,
                    icon: "clock.arrow.circlepath",
                    selected: store.source == .history) {
                    store.source = .history
                    store.selectFirst()
                }

                ForEach(store.pinboards) { board in
                    tab(id: board.id,
                        title: board.name,
                        dot: board.color,
                        icon: nil,
                        selected: store.source == .pinboard(board.id)) {
                        store.source = .pinboard(board.id)
                        store.selectFirst()
                    }
                    // Rename lived only in the context menu, which nobody found (#100).
                    .simultaneousGesture(TapGesture(count: 2).onEnded { rename(board) })
                    .help(L("Double-click or right-click to rename"))
                    .contextMenu {
                        Button(L("Rename…")) { rename(board) }
                        Button(L("Delete Pinboard"), role: .destructive) {
                            store.deletePinboard(board.id)
                        }
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
    }

    private func tab(id: UUID,
                     title: String,
                     dot: Color?,
                     icon: String?,
                     selected: Bool,
                     action: @escaping () -> Void) -> some View {
        let hovered = hoveredID == id
        return Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.chromeTextPrimary)
                }
                if let dot {
                    Circle()
                        .fill(dot)
                        .frame(width: 7, height: 7)
                }
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1)
                    // Paste prints the running source at full strength and the
                    // rest at secondary; the capsule carries the selection, not
                    // the text color.
                    .foregroundStyle(selected || hovered
                                     ? Theme.chromeTextPrimary
                                     : Theme.chromeTextSecondary)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background {
                if selected {
                    Capsule().fill(Theme.pillBG)
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

    private func addPinboard() {
        let board = store.addPinboard(name: L("New Pinboard"))
        store.source = .pinboard(board.id)
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
