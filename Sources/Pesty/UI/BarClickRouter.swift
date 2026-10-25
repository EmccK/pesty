import AppKit
import Foundation

/// Turns a click into a selection synchronously, at the window level.
///
/// SwiftUI's `onTapGesture(count: 2)` and `onTapGesture` cannot coexist without
/// the single tap waiting out the system double-click interval: as long as a
/// double-tap recognizer is attached to the same view, a single tap stays
/// "undecided" until the second click fails to arrive. `NSEvent.clickCount`
/// already knows the answer — it is 1 on the first click and 2 on the second —
/// so handling the event in `BarPanel.sendEvent` removes the wait entirely
/// instead of trying to out-order the recognizers.
///
/// The router needs to answer three questions and nothing else: which clip was
/// under the pointer, whether a modifier asked for a multi-selection, and
/// whether this is a first or second click.
@MainActor
final class BarClickRouter {
    /// Position of each card in the strip's content space, published by the
    /// card views as they layout. Only the entries the lazy stack has realized
    /// appear here, which is also the only set that can be clicked.
    struct CardSlot: Equatable {
        let id: UUID
        /// Frame in the strip's content space (the space the clip view scrolls).
        let contentFrame: CGRect
        /// Frame in SwiftUI's global space, which for a window-hosted view is
        /// window coordinates with the origin at the top left. Hit testing uses
        /// this one: it needs no conversion from the event, so the two sides
        /// cannot disagree about where the origin is.
        let globalFrame: CGRect
    }

    static let shared = BarClickRouter()

    /// The bar's own controls, as far as the click handler is concerned.
    ///
    /// Only the two regions a click can land on *while the search field is
    /// open* need naming: the field itself and the source row. Everything else
    /// in the panel is either a card (handled separately) or dead space.
    enum Chrome: String, CaseIterable {
        case search
        case tabs
    }

    private var slots: [CardSlot] = []
    private var chromeFrames: [Chrome: CGRect] = [:]

    /// Records one control's rectangle in window coordinates, the same space
    /// the card slots use.
    func registerChrome(_ region: Chrome, frame: CGRect) {
        if chromeFrames[region] != frame { chromeFrames[region] = frame }
    }

    /// True when `point` landed on a control the panel must not treat as dead
    /// space. An unregistered region simply is not on screen yet, which reads
    /// as dead space - the safe answer, because the search is only ever
    /// collapsed when it is open, and an open field has registered itself.
    func isOnChrome(_ point: CGPoint) -> Bool {
        chromeFrames.values.contains { $0.contains(point) }
    }

    /// Records one card's rectangle. Called from the card's layout pass, so the
    /// router always answers with the geometry the user is looking at.
    func register(id: UUID, contentFrame: CGRect, globalFrame: CGRect) {
        let slot = CardSlot(id: id, contentFrame: contentFrame, globalFrame: globalFrame)
        if let existing = slots.firstIndex(where: { $0.id == id }) {
            slots[existing] = slot
        } else {
            slots.append(slot)
        }
    }

    /// The recorded geometry for one card, or nil when the lazy stack has not
    /// realized it (nothing to scroll to, and nothing to compare against).
    func slot(for id: UUID) -> CardSlot? {
        slots.first { $0.id == id }
    }

    /// Drops a card that left the hierarchy. Without this a stale rectangle
    /// would keep answering clicks for a clip that scrolled out of the stack.
    func unregister(id: UUID) {
        slots.removeAll { $0.id == id }
    }

    func clear() {
        slots.removeAll(keepingCapacity: true)
    }

    /// The clip under `point`, given in window coordinates.
    ///
    /// Both axes are checked. Cards share one vertical band, so a click inside
    /// a card's horizontal span but in the padding below it is dead space — and
    /// so is a click on the card's own band, which the previous content-space
    /// version got wrong: the event was converted relative to the clip view's
    /// top while the frames carried the strip's padding origin, and every click
    /// on a card's title band missed by that offset.
    func clipID(atWindowPoint point: CGPoint) -> UUID? {
        slots.first { $0.globalFrame.contains(point) }?.id
    }
}
