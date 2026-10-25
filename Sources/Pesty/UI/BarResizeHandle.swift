import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The bar's top-edge handle, as the key monitor sees it.
///
/// The handle becomes the panel's first responder as soon as it is laid out,
/// because it is the outermost view that accepts first responder status. That
/// is correct for its own job — a vertical drag and the ten-point accessibility
/// steps are its keys to handle — but it must not swallow the bar's own keys
/// while it is idle. `isResizing` is what tells the two apart.
@MainActor
protocol BarResizeHandleResponder: AnyObject {
    var isResizing: Bool { get }
}

/// A drag target along the Paste Bar's top edge for resizing it vertically.
///
/// Drag callbacks use AppKit's global screen coordinate space so the owner can
/// keep its resize geometry independent of the handle's position in SwiftUI.
///
/// Paste has no visible grabber: its whole top edge is draggable, and the
/// pointer turns into a resize cursor over it. `showsGrip` keeps that behaviour
/// while still letting the old visible pill be turned on in Settings.
@MainActor
struct BarResizeHandle: View {
    private static let size = NSSize(width: 42, height: 14)

    /// The invisible edge is thinner than the visible grip so it cannot steal
    /// clicks from the top bar's controls.
    private static let edgeHeight: CGFloat = 10

    private let accessibilityValue: CGFloat?
    private let showsGrip: Bool
    private let onBegin: (NSPoint) -> Void
    private let onChange: (NSPoint) -> Void
    private let onEnd: (NSPoint) -> Void
    private let onCancel: () -> Void
    private let onAccessibilityAdjustment: (CGFloat) -> Void

    init(
        accessibilityValue: CGFloat? = nil,
        showsGrip: Bool = true,
        onBegin: @escaping (NSPoint) -> Void,
        onChange: @escaping (NSPoint) -> Void,
        onEnd: @escaping (NSPoint) -> Void,
        onCancel: @escaping () -> Void,
        onAccessibilityAdjustment: @escaping (CGFloat) -> Void
    ) {
        self.accessibilityValue = accessibilityValue
        self.showsGrip = showsGrip
        self.onBegin = onBegin
        self.onChange = onChange
        self.onEnd = onEnd
        self.onCancel = onCancel
        self.onAccessibilityAdjustment = onAccessibilityAdjustment
    }

    var body: some View {
        BarResizeHandleRepresentable(
            accessibilityValue: accessibilityValue,
            showsGrip: showsGrip,
            callbacks: .init(
                onBegin: onBegin,
                onChange: onChange,
                onEnd: onEnd,
                onCancel: onCancel,
                onAccessibilityAdjustment: onAccessibilityAdjustment))
        .frame(maxWidth: .infinity)
        .frame(height: showsGrip ? Self.size.height : Self.edgeHeight)
    }
}

@MainActor
private struct BarResizeHandleRepresentable: NSViewRepresentable {
    let accessibilityValue: CGFloat?
    let showsGrip: Bool
    let callbacks: BarResizeHandleView.Callbacks

    func makeNSView(context: Context) -> BarResizeHandleView {
        BarResizeHandleView(callbacks: callbacks,
                            accessibilityValue: accessibilityValue,
                            showsGrip: showsGrip)
    }

    func updateNSView(_ nsView: BarResizeHandleView, context: Context) {
        nsView.callbacks = callbacks
        nsView.accessibilityHeight = accessibilityValue
        nsView.showsGrip = showsGrip
    }
}

@MainActor
private final class BarResizeHandleView: NSView, BarResizeHandleResponder {
    static let accessibilityStep: CGFloat = 10

    struct Callbacks {
        let onBegin: (NSPoint) -> Void
        let onChange: (NSPoint) -> Void
        let onEnd: (NSPoint) -> Void
        let onCancel: () -> Void
        let onAccessibilityAdjustment: (CGFloat) -> Void
    }

    var callbacks: Callbacks
    var accessibilityHeight: CGFloat? {
        didSet { updateAccessibilityValue() }
    }
    var showsGrip = true {
        didSet { needsDisplay = true }
    }

    private var isTrackingDrag = false
    private var ownsResizeCursor = false
    private weak var previousFirstResponder: NSResponder?

    var isResizing: Bool { isTrackingDrag }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 14) }

    init(callbacks: Callbacks, accessibilityValue: CGFloat?, showsGrip: Bool = true) {
        self.callbacks = callbacks
        self.accessibilityHeight = accessibilityValue
        self.showsGrip = showsGrip
        super.init(frame: NSRect(x: 0, y: 0, width: 42, height: 14))

        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(L("Resize Paste Bar"))
        setAccessibilityHelp(L("Drag vertically, or increment and decrement in ten-point steps."))
        updateAccessibilityValue()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) unavailable")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsGrip else { return }
        let line = NSRect(x: bounds.midX - 21, y: bounds.midY - 2, width: 42, height: 4)
        NSColor.secondaryLabelColor.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: line, xRadius: 2, yRadius: 2).fill()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        guard !isTrackingDrag else { return }
        isTrackingDrag = true
        previousFirstResponder = window?.firstResponder
        window?.makeFirstResponder(self)
        NSCursor.resizeUpDown.push()
        ownsResizeCursor = true
        callbacks.onBegin(screenPoint(for: event))
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTrackingDrag else { return }
        callbacks.onChange(screenPoint(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        guard isTrackingDrag else { return }
        let point = screenPoint(for: event)
        finishTracking()
        callbacks.onEnd(point)
    }

    override func keyDown(with event: NSEvent) {
        guard isTrackingDrag, Int(event.keyCode) == kVK_Escape else {
            super.keyDown(with: event)
            return
        }
        cancelTracking()
    }

    override func cancelOperation(_ sender: Any?) {
        guard isTrackingDrag else {
            super.cancelOperation(sender)
            return
        }
        cancelTracking()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if isTrackingDrag, newWindow !== window {
            cancelTracking()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func accessibilityPerformIncrement() -> Bool {
        callbacks.onAccessibilityAdjustment(Self.accessibilityStep)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        callbacks.onAccessibilityAdjustment(-Self.accessibilityStep)
        return true
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard isTrackingDrag,
              let notificationWindow = notification.object as? NSWindow,
              notificationWindow === window else { return }
        cancelTracking()
    }

    private func cancelTracking() {
        guard isTrackingDrag else { return }
        finishTracking()
        callbacks.onCancel()
    }

    private func finishTracking() {
        isTrackingDrag = false
        if ownsResizeCursor {
            NSCursor.pop()
            ownsResizeCursor = false
        }
        // If the previous responder refuses, the window itself takes over;
        // the handle must never keep the bar's keys after a drag.
        if let window, window.firstResponder === self,
           !window.makeFirstResponder(previousFirstResponder) {
            window.makeFirstResponder(nil)
        }
        previousFirstResponder = nil
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        guard let eventWindow = event.window else { return NSEvent.mouseLocation }
        return eventWindow.convertPoint(toScreen: event.locationInWindow)
    }

    private func updateAccessibilityValue() {
        let value = accessibilityHeight.map { NSNumber(value: Double($0)) }
        setAccessibilityValue(value)
    }
}
