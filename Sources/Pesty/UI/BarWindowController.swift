import AppKit
import SwiftUI

final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if AppController.shared.handleBarCommandShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// The first place a click can be observed, before SwiftUI's gesture
    /// recognizers see it.
    ///
    /// Selection is handled here rather than with a tap gesture because a
    /// single tap sharing a view with `onTapGesture(count: 2)` cannot fire
    /// until the system double-click interval expires — measured as a 350 ms
    /// gap between mouse-up and the selection. `NSEvent.clickCount` settles
    /// the question immediately: 1 selects, 2 pastes.
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .leftMouseDown else {
            super.sendEvent(event)
            return
        }
        // Anything the strip does not claim — a search field, the pinboard
        // row, the traffic-button area — must keep its normal behaviour, so
        // only a click that lands on a card is consumed.
        guard let clipID = BarClickRouter.shared.clipID(atWindowPoint: windowPoint(of: event)) else {
            super.sendEvent(event)
            return
        }

        let store = ClipboardStore.shared
        guard let item = store.visibleItems.first(where: { $0.id == clipID }) else {
            super.sendEvent(event)
            return
        }

        // Control-click and right-click belong to the context menu, and the
        // drag source needs the event to begin a drag at all.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) || flags.contains(.shift) || flags.contains(.command) {
            super.sendEvent(event)
            return
        }

        if event.clickCount >= 2 {
            store.select(clipID)
            AppController.shared.pasteItem(item)
            return
        }

        store.select(clipID)

        // The event still goes through so `ScrollView` keeps its own gesture
        // state; the selection has already landed, which is the part that was
        // being waited on.
        super.sendEvent(event)
    }

    /// The event's location in the same space `CardSlotReporter` publishes.
    ///
    /// SwiftUI's `.global` space for a view inside a window places the origin at
    /// the window's top left with y growing downward; `locationInWindow` uses
    /// AppKit's bottom-left origin with y growing upward. Flipping here keeps a
    /// single conversion in one place instead of asking the layout again.
    private func windowPoint(of event: NSEvent) -> CGPoint {
        CGPoint(x: event.locationInWindow.x,
                y: frame.height - event.locationInWindow.y)
    }
}

@MainActor
final class BarWindowController: NSWindowController, NSWindowDelegate {

    /// Where the bar is in its show/hide cycle.
    ///
    /// This is the authoritative answer to "is the bar up?". `NSWindow.isVisible` used
    /// to serve that role, but it only returns to false inside an animation completion
    /// handler, and AppKit drops those handlers when a later animation supersedes them
    /// on the same property. One missed `orderOut` left the panel permanently
    /// "visible", so every hotkey press routed to `hide()` and the bar never came back
    /// until the app was relaunched. That is issue #64.
    private enum Phase: Equatable {
        case hidden
        case showing(Int)
        case shown
        case hiding(Int)
    }

    private var phase: Phase = .hidden
    private var epoch = 0
    private let searchBridge = BarSearchFieldBridge()
    private var targetVisibleFrame: NSRect?
    private var resizeSession: BarResizeSession?

    /// True while the bar is up or on its way up. `AppController.toggleBar` asks this
    /// instead of `window.isVisible`.
    var isPresented: Bool {
        switch phase {
        case .showing, .shown: return true
        case .hidden, .hiding: return false
        }
    }

    private static let showDuration: TimeInterval = 0.22
    private static let hideDuration: TimeInterval = 0.16

    init() {
        let panel = BarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 360),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        // Without this a stray close() would deallocate the panel and leave `window`
        // nil, which is another way to never show the bar again.
        panel.isReleasedWhenClosed = false
        let content = NSHostingView(rootView: BarView(searchBridge: searchBridge))
        if #available(macOS 26.0, *) {
            let glassContent = NSView()
            content.translatesAutoresizingMaskIntoConstraints = false
            glassContent.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: glassContent.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: glassContent.trailingAnchor),
                content.topAnchor.constraint(equalTo: glassContent.topAnchor),
                // The glass fills the window exactly: Paste's panel rounds all
                // four of its own corners, so the glass must draw them in view
                // instead of parking its lower curve below the window edge.
                content.bottomAnchor.constraint(equalTo: glassContent.bottomAnchor),
            ])

            let glass = NSGlassEffectView()
            glass.contentView = glassContent
            glass.cornerRadius = Theme.cornerRadius
            glass.tintColor = Theme.panelGlassTint
            glass.style = .regular
            panel.contentView = glass
            panel.hasShadow = false
        } else {
            // The HUD material is always dark, so pin the appearance dark:
            // the adaptive Theme tokens would otherwise resolve to their light
            // variants in light system mode and vanish against the HUD.
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.contentView = content
        }
        super.init(window: panel)
        panel.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    private var wheelMonitor: Any?

    /// SwiftUI's horizontal `ScrollView` only consumes horizontal scrolling, so
    /// a plain mouse wheel — vertical by nature — does nothing over the strip.
    /// Bending the vertical delta onto the strip's axis is what makes a wheel
    /// scroll the cards the way Paste's does.
    private func startWheelMonitor() {
        guard wheelMonitor == nil else { return }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.translateVerticalWheel(event) ? nil : event
        }
    }

    private func stopWheelMonitor() {
        guard let wheelMonitor else { return }
        NSEvent.removeMonitor(wheelMonitor)
        self.wheelMonitor = nil
    }

    private func translateVerticalWheel(_ event: NSEvent) -> Bool {
        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        // Horizontal swipes, and gestures that are already moving the strip,
        // are left alone.
        guard deltaY != 0, abs(deltaY) > abs(deltaX) else { return false }
        guard let scrollView = horizontalScrollView(at: event.locationInWindow),
              let document = scrollView.documentView else { return false }

        let clip = scrollView.contentView
        let limit = max(0, document.frame.width - clip.bounds.width)
        guard limit > 0 else { return false }

        // A notched wheel reports lines; a trackpad reports points.
        let step = event.hasPreciseScrollingDeltas ? deltaY : deltaY * 24
        let target = min(max(0, clip.bounds.origin.x - step), limit)
        guard target != clip.bounds.origin.x else { return false }

        clip.scroll(to: NSPoint(x: target, y: clip.bounds.origin.y))
        scrollView.reflectScrolledClipView(clip)
        return true
    }

    /// The strip's own scroll view, found by hit-testing what is under the
    /// pointer so wheel events over the top bar or the toolbar keep their
    /// normal behaviour.
    private func horizontalScrollView(at windowPoint: NSPoint) -> NSScrollView? {
        guard let content = window?.contentView else { return nil }
        var view = content.hitTest(content.convert(windowPoint, from: nil))
        while let current = view {
            if let scrollView = current as? NSScrollView { return scrollView }
            view = current.superview
        }
        return nil
    }

    /// The screen the bar should slide up from: the one under the pointer.
    ///
    /// `NSRect.contains` excludes a rect's max edges, so a pointer sitting exactly on
    /// the boundary between two displays matches none of them. Displays of differing
    /// sizes also leave unreachable gaps in the global coordinate space. Both cases
    /// used to fall through to `NSScreen.main`, which is the screen holding the *key
    /// window* — not the one the pointer is on — so the bar surfaced on the wrong
    /// display. Hit-test with `NSMouseInRect`, then fall back to the nearest screen.
    private static func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let hit = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return hit
        }
        return NSScreen.screens.min { a, b in
            distanceSquared(from: a.frame, to: mouse) < distanceSquared(from: b.frame, to: mouse)
        }
    }

    private static func distanceSquared(from rect: NSRect, to point: NSPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    /// Bumps the transition counter so any completion still in flight becomes stale.
    private func beginTransition() -> Int {
        epoch &+= 1
        return epoch
    }

    /// Runs `body` exactly once for the transition identified by `token`, and never for
    /// a transition that has already been superseded.
    ///
    /// Both the animation completion handler and a backstop timer call through here.
    /// The timer is what actually guarantees progress - AppKit drops completion handlers
    /// when a later animation replaces them, and relying on one to run was the original
    /// bug. Bumping `epoch` on settle makes the second caller for the same token a no-op.
    private func settle(_ token: Int, _ body: () -> Void) {
        guard epoch == token else { return }
        epoch &+= 1
        body()
    }

    func show() {
        guard let panel = window else { return }
        guard let screen = Self.targetScreen() else { return }
        panel.level = Settings.shared.hideOnClickOutside ? .modalPanel : .floating
        let vf = screen.visibleFrame
        let onScreen = BarResizeGeometry.panelFrame(
            for: Settings.shared.barHeight,
            in: vf
        )
        let height = onScreen.height
        targetVisibleFrame = vf
        resizeSession = nil

        // The panel stays parked at its final frame and the content slides up *inside*
        // it. Animating the window frame itself is not safe on multi-display setups:
        // the old staging rect (vf.minY - height) is only genuinely off-screen when
        // nothing sits below the target display. With displays stacked vertically it
        // lands on the neighbouring screen, so the bar appeared there in full and then
        // flew across the bezel. A view clipped to the window can never escape it.
        panel.setFrame(onScreen, display: false)
        guard let content = panel.contentView else { return }
        let contentHeight = height
        content.autoresizingMask = []
        content.frame = NSRect(x: 0, y: -contentHeight,
                               width: onScreen.width, height: contentHeight)

        let token = beginTransition()
        phase = .showing(token)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        startWheelMonitor()

        let finish: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.settle(token) {
                self.phase = .shown
                // The panel can lose key focus while it is still animating up, and
                // windowDidResignKey ignores that because the bar is not .shown yet.
                // Catch it here so the bar does not sit on screen unfocused forever.
                if Settings.shared.hideOnClickOutside,
                   panel.isVisible, !panel.isKeyWindow, !AppController.shared.suppressAutoHide {
                    AppController.shared.hideBar()
                }
            }
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.showDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            content.animator().frame = BarResizeGeometry.presentedContentFrame(
                panelSize: onScreen.size
            )
        }, completionHandler: { DispatchQueue.main.async(execute: finish) })
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDuration + 0.05, execute: finish)
    }

    func hide() {
        guard let panel = window, let content = panel.contentView else { return }
        guard isPresented else { return }
        stopWheelMonitor()
        cancelBarResize()

        let token = beginTransition()
        phase = .hiding(token)
        let down = NSRect(x: 0, y: -content.frame.height,
                          width: content.frame.width, height: content.frame.height)

        let finish: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.settle(token) {
                panel.orderOut(nil)
                self.phase = .hidden
            }
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.hideDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            content.animator().frame = down
        }, completionHandler: { DispatchQueue.main.async(execute: finish) })
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDuration + 0.05, execute: finish)
    }

    /// Drops the bar with no animation and no completion handler to depend on.
    /// Used after sleep or a display change, where an in-flight transition can be
    /// left stranded on a screen that no longer exists.
    func forceHide() {
        stopWheelMonitor()
        resizeSession = nil
        _ = beginTransition()
        phase = .hidden
        window?.orderOut(nil)
    }

    var searchOwnsFirstResponder: Bool {
        searchBridge.ownsFirstResponder(in: window)
    }

    @discardableResult
    func focusSearchAtEnd() -> Bool {
        searchBridge.focusAtEnd()
    }

    func resignSearch() {
        searchBridge.resign()
    }

    func beginBarResize(at screenPoint: NSPoint) {
        guard phase == .shown,
              resizeSession == nil,
              let panel = window,
              let visibleFrame = targetVisibleFrame else { return }
        resizeSession = BarResizeSession(
            initialPanelHeight: panel.frame.height,
            initialScreenY: screenPoint.y,
            visibleFrame: visibleFrame
        )
    }

    func updateBarResize(at screenPoint: NSPoint) {
        guard phase == .shown, let resizeSession else { return }
        applyResizeFrame(resizeSession.frame(atScreenY: screenPoint.y))
    }

    func endBarResize(at screenPoint: NSPoint) {
        guard phase == .shown, let resizeSession else { return }
        let frame = resizeSession.frame(atScreenY: screenPoint.y)
        let persistedHeight = resizeSession.finalPersistedHeight(atScreenY: screenPoint.y)
        self.resizeSession = nil
        applyResizeFrame(frame)
        Settings.shared.barHeight = persistedHeight
    }

    func cancelBarResize() {
        guard let resizeSession else { return }
        self.resizeSession = nil
        guard phase == .shown else { return }
        applyResizeFrame(resizeSession.cancelledFrame)
    }

    func adjustBarHeight(by delta: CGFloat) {
        guard phase == .shown,
              resizeSession == nil,
              let panel = window,
              let visibleFrame = targetVisibleFrame else { return }
        let requested = Double(panel.frame.height + delta)
        let frame = BarResizeGeometry.panelFrame(for: requested, in: visibleFrame)
        applyResizeFrame(frame)
        Settings.shared.barHeight = Double(frame.height)
    }

    /// `display: false` while a drag is in flight: the live resize session
    /// calls this for every pointer sample, and asking AppKit to flush the
    /// window and its SwiftUI-hosted content synchronously each time is what
    /// made the bar drag behind the pointer. The final frame is drawn by the
    /// next run-loop turn, and a discrete keyboard step still coalesces fine.
    private func applyResizeFrame(_ frame: NSRect) {
        guard let panel = window, let content = panel.contentView,
              frame.width > 0, frame.height > 0 else { return }
        panel.setFrame(frame, display: false)
        content.frame = BarResizeGeometry.presentedContentFrame(
            panelSize: frame.size
        )
    }

    func windowDidResignKey(_ notification: Notification) {
        guard Settings.shared.hideOnClickOutside,
              phase == .shown,
              !AppController.shared.suppressAutoHide else { return }
        AppController.shared.hideBar()
    }
}
