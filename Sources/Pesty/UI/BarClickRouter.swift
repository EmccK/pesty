import AppKit
import Foundation
import SwiftUI

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
    /// Click traces in Console (`Pesty.click`). Set to `true` while chasing a selection miss.
    static var logsClicks = false

    /// Position of each realized card, in window coordinates with a top-left
    /// origin — the same space `BarPanel` converts the click into.
    struct CardSlot: Equatable {
        let id: UUID
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
    private let probes = NSHashTable<CardFrameProbe>.weakObjects()

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

    func track(_ probe: CardFrameProbe) {
        probes.add(probe)
    }

    /// Drops a card that left the hierarchy. A stale rectangle used to keep
    /// answering clicks, and the click was then thrown away because that id
    /// was no longer on screen.
    func untrack(_ probe: CardFrameProbe) {
        let id = probe.clipID
        probe.clipID = nil
        probes.remove(probe)
        guard let id else { return }
        if !probes.allObjects.contains(where: { $0.clipID == id }) {
            slots.removeAll { $0.id == id }
        }
    }

    /// Re-reads every card from AppKit. Scroll moves the views without
    /// invalidating the SwiftUI geometry that used to be cached here, so a
    /// click has to sample the views it is about to test.
    func refreshFrames() {
        var live = Set<UUID>()
        for probe in probes.allObjects {
            guard let id = probe.clipID, let frame = probe.currentFrame() else { continue }
            let slot = CardSlot(id: id, globalFrame: frame)
            if let existing = slots.firstIndex(where: { $0.id == id }) {
                slots[existing] = slot
            } else {
                slots.append(slot)
            }
            live.insert(id)
        }
        slots.removeAll { !live.contains($0.id) }
    }

    /// The recorded geometry for one card, or nil when the lazy stack has not
    /// realized it (nothing to scroll to, and nothing to compare against).
    func slot(for id: UUID) -> CardSlot? {
        refreshFrames()
        return slots.first { $0.id == id }
    }

    func clear() {
        slots.removeAll(keepingCapacity: true)
    }

    /// The visible clip under `point`, in top-left window coordinates.
    ///
    /// A slot that scrolled away used to stay registered and win `slots.first`,
    /// after which the click was discarded because that id was no longer
    /// visible. Hits are limited to `visibleIDs`, and an overlap is broken by
    /// the card whose center is nearest the pointer.
    func clipID(atWindowPoint point: CGPoint, visibleIDs: Set<UUID>) -> UUID? {
        refreshFrames()
        let hits = slots.map { CardHit(id: $0.id, frame: $0.globalFrame) }
        return CardHitTesting.bestID(at: point, slots: hits, visibleIDs: visibleIDs)
    }

    static func log(_ message: String) {
        guard logsClicks else { return }
        NSLog("%@", "Pesty.click \(message)" as NSString)
    }

    func trace(
        point: CGPoint,
        raw: CGPoint,
        clickCount: Int,
        flags: NSEvent.ModifierFlags,
        visibleIDs: Set<UUID>,
        action: String
    ) {
        guard Self.logsClicks else { return }
        let described = slots.map { slot in
            let inside = CardHitTesting.contains(slot.globalFrame, point)
            let distance = Int(CardHitTesting.distance(slot.globalFrame, point).rounded())
            return "\(slot.id.uuidString) \(Self.rectText(slot.globalFrame)) inside=\(inside) d=\(distance) visible=\(visibleIDs.contains(slot.id))"
        }.joined(separator: " || ")
        Self.log(
            "point=(\(Self.num(point.x)),\(Self.num(point.y))) raw=(\(Self.num(raw.x)),\(Self.num(raw.y))) count=\(clickCount) flags=\(Self.flagText(flags)) probes=\(probes.allObjects.count) slots=\(slots.count) [\(described)] action=\(action)"
        )
    }

    private static func num(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    private static func rectText(_ rect: CGRect) -> String {
        "(\(num(rect.minX)),\(num(rect.minY)) \(num(rect.width))x\(num(rect.height)))"
    }

    private static func flagText(_ flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.command) { parts.append("cmd") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.option) { parts.append("opt") }
        if flags.contains(.control) { parts.append("ctrl") }
        return parts.isEmpty ? "-" : parts.joined(separator: "+")
    }
}

struct CardHit: Equatable {
    let id: UUID
    let frame: CGRect
}

enum CardHitTesting {
    static func bestID(at point: CGPoint, slots: [CardHit], visibleIDs: Set<UUID>) -> UUID? {
        let hits = slots.enumerated().filter { _, slot in
            visibleIDs.contains(slot.id) && contains(slot.frame, point)
        }
        return hits.min { a, b in
            let da = distance(a.element.frame, point)
            let db = distance(b.element.frame, point)
            if da != db { return da < db }
            let aa = a.element.frame.width * a.element.frame.height
            let ab = b.element.frame.width * b.element.frame.height
            if aa != ab { return aa < ab }
            return a.offset > b.offset
        }?.element.id
    }

    /// Includes the max edges. `CGRect.contains` does not, so a click on the
    /// card's trailing or bottom edge used to miss.
    static func contains(_ frame: CGRect, _ point: CGPoint) -> Bool {
        frame.width > 1 && frame.height > 1
            && point.x >= frame.minX && point.x <= frame.maxX
            && point.y >= frame.minY && point.y <= frame.maxY
    }

    static func distance(_ frame: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = frame.midX - point.x
        let dy = frame.midY - point.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// One card's rectangle, read from AppKit at click time.
///
/// SwiftUI's `frame(in:)` was sampled when the card appeared and then left
/// behind: the named coordinate space it watched was never installed, and the
/// scroll view does not post bounds changes unless asked. After a scroll the
/// cached rectangle no longer covered the card, so the click missed.
final class CardFrameProbe: NSView {
    var clipID: UUID?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    /// Window coordinates, origin at the top left, matching `BarPanel.windowPoint`.
    func currentFrame() -> CGRect? {
        guard let window, bounds.width > 1, bounds.height > 1 else { return nil }
        let inWindow = convert(bounds, to: nil)
        guard inWindow.width > 1, inWindow.height > 1 else { return nil }
        return CGRect(
            x: inWindow.minX,
            y: window.frame.height - inWindow.maxY,
            width: inWindow.width,
            height: inWindow.height
        )
    }
}

struct CardSlotReporter: NSViewRepresentable {
    let id: UUID

    func makeNSView(context: Context) -> CardFrameProbe {
        let view = CardFrameProbe()
        view.clipID = id
        BarClickRouter.shared.track(view)
        return view
    }

    func updateNSView(_ view: CardFrameProbe, context: Context) {
        view.clipID = id
        BarClickRouter.shared.track(view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CardFrameProbe, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width > 1, height > 1 else { return nil }
        return CGSize(width: width, height: height)
    }

    static func dismantleNSView(_ view: CardFrameProbe, coordinator: ()) {
        BarClickRouter.shared.untrack(view)
    }
}
