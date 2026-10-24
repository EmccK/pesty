import CoreGraphics

/// Pure sizing rules shared by the Paste Bar's persisted preference and its
/// live-resize interaction.
enum BarResizeGeometry {
    /// Paste's own bar measures 337 pt tall, which leaves its square cards at
    /// 252 pt. Pesty spends a little more height on the top bar, so the default
    /// is raised a notch — with the current chrome (a 48 pt top bar over the
    /// strip's 12 and 27 pt padding) 349 pt lands the cards on 262 pt. Landing
    /// on Paste's exact 252 would put the default at 339.
    static let defaultHeight = 349.0
    static let minimumHeight = 300.0
    static let maximumHeight = 720.0

    /// Returns a value which is safe to persist independently of the display
    /// the bar happens to be shown on.
    static func normalizedPersistedHeight(_ height: Double) -> Double {
        guard height.isFinite else { return defaultHeight }
        return min(maximumHeight, max(minimumHeight, height))
    }

    /// Paste floats its bar a hair off the screen edges: measured live, its
    /// panel clears the left, right, and bottom of the visible frame by the
    /// same ~8 pt, and its bottom corners stay visible above whatever sits
    /// below the bar.
    static let sideInset: CGFloat = 8
    static let bottomInset: CGFloat = 8

    /// Narrow displays trade margin for width rather than collapsing the bar.
    private static let minimumPanelWidth: CGFloat = 480

    /// Applies the portable preference range first, then caps the result to
    /// the usable height of the target display. The bottom inset is spent
    /// before the panel is placed, so it comes out of the usable height too.
    static func effectiveHeight(
        for requestedHeight: Double,
        in visibleFrame: CGRect
    ) -> CGFloat {
        let displayHeight = visibleFrame.height
        guard displayHeight.isFinite, displayHeight > 0 else { return 0 }
        let usableHeight = max(0, displayHeight - bottomInset)
        return min(CGFloat(normalizedPersistedHeight(requestedHeight)), usableHeight)
    }

    /// The panel frame with the side and bottom margins applied, sharing the
    /// insets with every code path that rebuilds a frame from a visible frame.
    static func insetFrame(height: CGFloat, in visibleFrame: CGRect) -> CGRect {
        let inset = min(sideInset, max(0, (visibleFrame.width - minimumPanelWidth) / 2))
        return CGRect(
            x: visibleFrame.minX + inset,
            y: visibleFrame.minY + bottomInset,
            width: visibleFrame.width - inset * 2,
            height: height
        )
    }

    /// Produces the complete bottom-docked panel frame for a target display.
    static func panelFrame(
        for requestedHeight: Double,
        in visibleFrame: CGRect
    ) -> CGRect {
        insetFrame(
            height: effectiveHeight(for: requestedHeight, in: visibleFrame),
            in: visibleFrame
        )
    }

    /// The content view exactly fills the panel: the glass draws all four
    /// rounded corners in view, like Paste's floating panel.
    static func presentedContentFrame(panelSize: CGSize) -> CGRect {
        CGRect(x: 0, y: 0, width: panelSize.width, height: panelSize.height)
    }
}

/// Immutable state captured at mouse-down so live resizing does not feed the
/// moving panel geometry back into the drag calculation.
struct BarResizeSession: Equatable {
    let initialPanelHeight: CGFloat
    let initialScreenY: CGFloat
    let visibleFrame: CGRect

    init(
        initialPanelHeight: CGFloat,
        initialScreenY: CGFloat,
        visibleFrame: CGRect
    ) {
        self.visibleFrame = visibleFrame
        self.initialPanelHeight = BarResizeGeometry.effectiveHeight(
            for: Double(initialPanelHeight),
            in: visibleFrame
        )
        self.initialScreenY = initialScreenY
    }

    /// Global macOS screen coordinates increase upward, so upward pointer
    /// travel adds to the bar height and downward travel subtracts from it.
    func height(atScreenY screenY: CGFloat) -> CGFloat {
        guard initialScreenY.isFinite, screenY.isFinite else {
            return initialPanelHeight
        }
        let requestedHeight = initialPanelHeight + (screenY - initialScreenY)
        return BarResizeGeometry.effectiveHeight(
            for: Double(requestedHeight),
            in: visibleFrame
        )
    }

    func frame(atScreenY screenY: CGFloat) -> CGRect {
        BarResizeGeometry.insetFrame(height: height(atScreenY: screenY), in: visibleFrame)
    }

    /// The portable value to write only after a successful drag completes.
    func finalPersistedHeight(atScreenY screenY: CGFloat) -> Double {
        BarResizeGeometry.normalizedPersistedHeight(
            Double(height(atScreenY: screenY))
        )
    }

    var cancelledHeight: CGFloat { initialPanelHeight }

    var cancelledFrame: CGRect {
        BarResizeGeometry.insetFrame(height: initialPanelHeight, in: visibleFrame)
    }
}
