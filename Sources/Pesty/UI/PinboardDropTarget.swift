import AppKit
import SwiftUI

/// Takes a clip dragged out of the strip and drops it on a board.
///
/// AppKit, not SwiftUI's `onDrop`, because the work has to finish inside the
/// mouse-up. `performDragOperation` returning is what ends the drag session, and
/// the session is what owns the drag image, so answering here puts the image
/// away on the release frame.
///
/// The SwiftUI path measured badly: with `onDrop`, `perform` ran 4 ms after the
/// mouse came up, the pin itself took 0.1 ms, and a full-screen Pesty window
/// that appeared when the drag began stayed on screen for another 334-411 ms -
/// which is what read as the card hanging there after the release. The main
/// thread was idle throughout, so the delay was not our work; the measurement
/// does not say which part of the session's teardown it was, only that doing the
/// drop inside `performDragOperation` removes it.
///
/// The view is invisible and takes no clicks: `hitTest` answers only while one
/// of our own cards is in flight, which is also the only moment the tab should
/// react to a drop. Every other event falls through to the SwiftUI button
/// underneath, so selecting and renaming a board still work.
@MainActor
final class PinboardDropTargetView: NSView {
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}
    var onDrop: () -> Bool = { false }

    private static let clipType = NSPasteboard.PasteboardType(ClipDragProvider.clipType.identifier)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([Self.clipType])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Only a drag of one of our own cards belongs to this view.
    ///
    /// AppKit finds a drag destination by hit-testing the window, so returning
    /// nil here is what keeps the drop target from swallowing clicks meant for
    /// the tab. `draggedItemID` is stamped when a card's drag begins and
    /// cleared when the drop lands, the drag is cancelled, or the bar hides.
    ///
    /// The stamp alone is not enough to go on. A drag cancelled inside the
    /// strip never enters this view, so `draggingEnded` never runs here; a drag
    /// dropped on another app leaves this view out of the session entirely. In
    /// both cases the stamp survives, and a hit test that trusted it would let
    /// this invisible overlay hold the whole tab: `NSView.mouseDown` does
    /// nothing, so the next click on any tab would be swallowed and even hover
    /// would stop, until the bar was hidden and shown again. Gating on the
    /// event type as well means a stale stamp costs at most one discarded
    /// event, and the stamp is cleared on the way out.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard ClipDragProvider.draggedItemID != nil else { return nil }
        switch NSApp.currentEvent?.type {
        case .leftMouseDragged, .leftMouseUp:
            return super.hitTest(point)
        default:
            ClipDragProvider.clearDraggedItem()
            return nil
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard accepts(sender) else { return [] }
        onEnter()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        accepts(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onExit()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onExit()
        // A cancelled drag never reaches `performDragOperation`, and a stale
        // stamp would make this view claim the next plain click on the tab.
        ClipDragProvider.clearDraggedItem()
    }

    /// Runs the pin inside AppKit's drag callback, which means the store and the
    /// tab's `@State` change while SwiftUI is not driving the update. That is
    /// the point - returning from here is what ends the session - but it is also
    /// a reentrant write: if SwiftUI ever complains about modifying state during
    /// a view update, defer the write by one runloop turn. The session still
    /// ends on this frame; only the visible bookkeeping moves.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onExit()
        return onDrop()
    }

    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.types?.contains(Self.clipType) ?? false
    }
}

/// Hosts a `PinboardDropTargetView` behind a SwiftUI tab.
struct PinboardDropTarget: NSViewRepresentable {
    let onEnter: () -> Void
    let onExit: () -> Void
    let onDrop: () -> Bool

    func makeNSView(context: Context) -> PinboardDropTargetView {
        PinboardDropTargetView(frame: .zero)
    }

    func updateNSView(_ view: PinboardDropTargetView, context: Context) {
        view.onEnter = onEnter
        view.onExit = onExit
        view.onDrop = onDrop
    }
}
