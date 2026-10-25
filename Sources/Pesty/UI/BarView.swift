import SwiftUI

struct BarView: View {
    let searchBridge: BarSearchFieldBridge
    @Bindable private var store = ClipboardStore.shared
    @Bindable private var settings = Settings.shared

    /// Strip geometry, published once per size change. The "is this card on
    /// screen" test needs both, and reading them out of the live layout from a
    /// click handler would trade one layout pass for another.
    @State private var stripVisibleWidth: CGFloat?
    @State private var cardSide: CGFloat = Theme.cardMinSide
    /// The strip's scroll view, captured by `StripScrollViewProbe`. Weak is not
    /// enough — SwiftUI rebuilds the hierarchy freely — but holding it strongly
    /// would keep the view alive past the bar's teardown, so the probe hands it
    /// over and clears the reference when it leaves the hierarchy.
    @State private var stripScrollView: NSScrollView?

    private var searchIsActive: Bool {
        store.barInputMode == .search || !store.searchText.isEmpty
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { store.searchText },
            set: { AppController.shared.updateBarSearchText($0) }
        )
    }

    var body: some View {
        panelLayers
            .ignoresSafeArea()
    }

    private var panelLayers: some View {
        ZStack {
            panelBackground
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                topBar
                strip
            }
        }
        .overlay(alignment: .top) {
            // Paste has no grabber: its whole top edge drags. The edge is
            // always live, and Settings only decides whether the pill shows.
            BarResizeHandle(
                accessibilityValue: CGFloat(settings.barHeight),
                showsGrip: settings.showBarResizeHandle,
                onBegin: AppController.shared.beginBarResize,
                onChange: AppController.shared.updateBarResize,
                onEnd: AppController.shared.endBarResize,
                onCancel: AppController.shared.cancelBarResize,
                onAccessibilityAdjustment: AppController.shared.adjustBarHeight)
        }
        .clipShape(RoundedCorners(radius: Theme.cornerRadius,
                                  corners: [.topLeft, .topRight, .bottomLeft, .bottomRight]))
    }

    @ViewBuilder
    private var panelBackground: some View {
        if #available(macOS 26.0, *) {
            // The glass panel provides the blur; the wash pins its value so a
            // dark bar does not collapse into the desktop behind it.
            Theme.panelWash
        } else {
            VisualEffectView(material: .hudWindow)
            Theme.panelTint
        }
    }

    private var topBar: some View {
        // Paste's own row: the search control and the sources travel together
        // as one cluster in the middle of the bar, the transient actions sit to
        // its left, and the overflow menu holds the trailing edge. Equal spacers
        // keep the cluster centered between those edge actions instead of
        // pinning the sources to the leading edge.
        HStack(spacing: 6) {
            Spacer(minLength: 8)

            if store.multiSelectedIDs.count > 1 {
                bulkDeleteButton
            }
            if store.hasUndoableDeletion {
                undoButton
            }

            searchField
            PinboardTabs()

            Spacer(minLength: 8)

            #if MAS
            if settings.cloudKitSync { syncButton }
            #else
            if settings.iCloudSync { syncButton }
            #endif
            moreMenu
        }
        .padding(.horizontal, 18)
        .frame(height: Theme.topBarHeight)
    }

    private var syncButton: some View {
        Button {
            AppController.shared.toggleICloudSync()
        } label: {
            Image(systemName: settings.iCloudSync ? "checkmark.icloud.fill" : "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(settings.iCloudSync ? Theme.selection : Theme.chromeTextSecondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(settings.iCloudSync ? L("iCloud sync on") : L("Turn on iCloud sync"))
    }

    /// Paste's search affordance: a bare magnifying glass that expands in
    /// place into a right-aligned field and takes focus.
    ///
    /// The native field stays mounted even while collapsed. The key monitor
    /// focuses it synchronously and returns the very first keystroke to it, so
    /// type-anywhere search never loses a character to the transition; a view
    /// that only existed after the click would swallow that character.
    private var searchField: some View {
        HStack(spacing: 6) {
            Button {
                AppController.shared.beginBarSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(searchIsActive ? Theme.chromeTextPrimary : Theme.chromeTextSecondary)
                    .frame(width: 22, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Search"))
            .accessibilityLabel(L("Search"))
            // Collapsed, this is the only search affordance on screen.
            .opacity(searchIsActive ? 0 : 1)
            .frame(width: searchIsActive ? 0 : 22)
            .allowsHitTesting(!searchIsActive)

            NativeBarSearchField(
                text: searchTextBinding,
                bridge: searchBridge,
                onBegin: { AppController.shared.setBarSearchEditing(true) },
                onEnd: { AppController.shared.setBarSearchEditing(false) },
                onSubmit: { AppController.shared.pasteSelected() },
                onCancel: { AppController.shared.cancelBarSearchOrHide() },
                onMoveSelection: { store.moveSelection(by: $0) }
            )
            .frame(width: searchIsActive ? 200 : 0, height: 22)
            .opacity(searchIsActive ? 1 : 0)
            .allowsHitTesting(searchIsActive)
            .accessibilityHidden(!searchIsActive)

            if searchIsActive {
                Button {
                    AppController.shared.clearBarSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.chromeTextTertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Clear search"))
                .accessibilityLabel(L("Clear search"))
            }
        }
        // Paste's expanded field is a 28 pt capsule in the same gray the tab
        // selection uses; collapsed, the control is just the glyph.
        .padding(.horizontal, searchIsActive ? 9 : 2)
        .frame(height: 28)
        .background(searchIsActive ? Theme.pillBG : Color.clear, in: Capsule())
        // An active query keeps its width over the tab strip's ScrollView,
        // which is infinitely flexible and would otherwise squeeze the field.
        .layoutPriority(searchIsActive ? 2 : 0)
        // Scoped to this row. The same `.animation(value:)` on the top bar would
        // turn every geometry change in the subtree into an animated one.
        .animation(.easeOut(duration: 0.15), value: searchIsActive)
    }

    private var bulkDeleteButton: some View {
        let count = store.multiSelectedIDs.count
        return Button(role: .destructive) {
            AppController.shared.deleteEffectiveSelection()
        } label: {
            Label(L("Delete %ld", count), systemImage: "trash")
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .help(L("Delete %ld selected clips (⌘⌫)", count))
        .accessibilityLabel(L("Delete %ld selected clips", count))
    }

    private var undoButton: some View {
        Button {
            store.undoLastDelete()
        } label: {
            Label(L("Undo"), systemImage: "arrow.uturn.backward")
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .help(L("Undo the last deletion (⌘Z), available for 5 minutes"))
        .accessibilityLabel(L("Undo last deletion"))
    }

    private var moreMenu: some View {
        Menu {
            Button { AppController.shared.showSettings() } label: {
                Label(L("Settings…"), systemImage: "gearshape")
            }
            Button { store.clearHistory() } label: {
                Label(L("Clear History"), systemImage: "trash")
            }
            Divider()
            Button { AppController.shared.showAbout() } label: {
                Label(L("About Pesty"), systemImage: "info.circle")
            }
            Button { NSApp.terminate(nil) } label: {
                Label(L("Quit Pesty"), systemImage: "power")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.chromeTextSecondary)
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 34)
        .fixedSize()
    }

    /// Identifies the padded scroll content, so a presentation reset can land
    /// on the strip's natural resting offset - anchoring the first card's
    /// leading edge instead would scroll the horizontal inset out of view.
    private static let stripStartID = "stripStart"

    /// Coordinate space the cards report their frames in: the scroll view's
    /// own content space, so a frame's `minX` moves as the strip scrolls and
    /// `0...stripWidth` is the visible window.
    static let stripSpace = "pestyStripSpace"

    private var strip: some View {
        GeometryReader { geometry in
            let side = Self.cardSide(forStripHeight: geometry.size.height)
            let _ = publishStripGeometry(width: geometry.size.width, side: side)
            // Square cards of `side` need `side + paddings` of strip height.
            // The scroll view used to size itself to the taller of that and
            // the row's measured intrinsic width-driven height; here the
            // height is stated once and never re-measured.
            let rowHeight = side + Theme.stripTopPadding + Theme.stripBottomPadding
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Theme.cardSpacing) {
                        // A `ForEach` over the snapshot: the previous shape
                        // built `Array(enumerated())` and asked
                        // `isSelected` per card inside the loop, so every
                        // selection change re-diffed the whole strip and
                        // re-evaluated the view body of every visible card.
                        // `ClipCardView` reads the selection itself now, which
                        // keeps the strip's own body out of that path.
                        ForEach(store.visibleItems, id: \.id) { item in
                            ClipCardView(item: item, side: side)
                                .id(item.id)
                                .background {
                                    // Reports the card's rectangle in content
                                    // space so the window-level click router can
                                    // answer "which clip is under the pointer"
                                    // without asking the layout mid-click.
                                    CardSlotReporter(id: item.id, side: side)
                                }
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.92).combined(with: .opacity),
                                    removal: .opacity))
                        }
                    }
                    .padding(.horizontal, Theme.cardStripHorizontalPadding)
                    .padding(.top, Theme.stripTopPadding)
                    .padding(.bottom, Theme.stripBottomPadding)
                    // Paste hangs its cards from the top bar; without this the
                    // scroll view centers a shorter-than-viewport strip.
                    .frame(height: rowHeight, alignment: .top)
                    // Keyed on the ids, not the count: an insertion at the
                    // head and a trim at the tail leave the count unchanged,
                    // and the strip still needs its layout transition. Keying
                    // on the array also stops an unchanged strip from being
                    // re-animated when only selection moved.
                    .animation(.spring(response: 0.34, dampingFraction: 0.8),
                               value: store.visibleItems.map(\.id))
                    .id(Self.stripStartID)
                }
                // The scroll view itself, so the probe can find it and the
                // click path can read the live clip view offset.
                .background(StripScrollViewProbe { scrollView in
                    stripScrollView = scrollView
                })
                .onChange(of: store.barPresentationToken) { _, _ in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(Self.stripStartID, anchor: .leading)
                    }
                }
                .onChange(of: store.selectedID) { old, new in
                    guard let new else { return }
                    selectionDidMove(from: old, to: new, proxy: proxy)
                }
                .onChange(of: settings.selectedClipPosition) { _, _ in
                    // The user just changed the policy: always honour it, even
                    // in the "don't scroll" mode, so switching back to a
                    // centering mode visibly re-parks the strip.
                    guard let id = store.selectedID else { return }
                    scrollTo(id, proxy: proxy, animated: true)
                }
                .overlay { if store.visibleItems.isEmpty { emptyState } }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// Publishes strip geometry only when it actually changes, so a resize
    /// drag does not write `@State` on every frame.
    private func publishStripGeometry(width: CGFloat, side: CGFloat) {
        let roundedWidth = width.rounded()
        let roundedSide = side.rounded()
        if stripVisibleWidth != roundedWidth {
            stripVisibleWidth = roundedWidth
        }
        if cardSide != roundedSide {
            cardSide = roundedSide
        }
    }

    /// Paste's cards are square and sized from the room the strip has: the bar
    /// can be dragged taller and the cards grow with it.
    static func cardSide(forStripHeight height: CGFloat) -> CGFloat {
        let available = height - Theme.stripTopPadding - Theme.stripBottomPadding
        guard available.isFinite, available > 0 else { return Theme.cardMinSide }
        return min(Theme.cardMaxSide, max(Theme.cardMinSide, available))
    }

    /// Decides whether a selection change moves the strip, and how.
    ///
    /// Two questions are answered separately:
    ///
    /// 1. *Should the strip move at all?* In `keepVisible` it only moves for a
    ///    clip that is not already on screen — clicking through the visible row
    ///    leaves the strip perfectly still under the pointer. In the centering
    ///    modes every selection re-parks the strip, which is what made a click
    ///    on a side card slide the whole row.
    /// 2. *How far?* A selection that moved by one step (an arrow key, or a
    ///    click on the neighbouring card) should nudge the strip, not cause it
    ///    to sprint across the row. Both modes therefore ask for the smallest
    ///    scroll that satisfies the anchor instead of a full re-centre.
    private func selectionDidMove(from old: UUID?, to new: UUID, proxy: ScrollViewProxy) {
        guard settings.selectedClipPosition.centersOnEverySelection else {
            // "Don't scroll": the card is already on screen in the overwhelming
            // majority of clicks, and a no-op scroll is still a layout pass.
            guard !isOnScreen(new) else { return }
            scrollTo(new, proxy: proxy, animated: true)
            return
        }
        _ = old
        scrollTo(new, proxy: proxy, animated: !store.isFastSelectionRun)
    }

    /// True when the card sits wholly inside the strip's visible window.
    ///
    /// Both sides come from the same place: the router records each realized
    /// card's rectangle in window coordinates, and the clip view reports the
    /// window rectangle it is showing. The strip used to recompute a card's
    /// position from its index and compare it against a scroll offset, which
    /// made two independent derivations of "where is this card" that could —
    /// and did — disagree.
    ///
    /// A card peeking in from either edge is *not* on screen: it still needs
    /// the scroll that brings it fully into view, or the selection stays cut
    /// off. When the router has no rectangle for the id the answer is false,
    /// which sends the caller down the ordinary scroll path rather than
    /// guessing.
    private func isOnScreen(_ id: UUID) -> Bool {
        guard let slot = BarClickRouter.shared.slot(for: id),
              let scrollView = stripScrollView,
              let window = scrollView.contentView.window else { return false }
        // The clip view's own frame is the visible window, in the same
        // coordinate space the router recorded the card in.
        let clip = scrollView.contentView
        let visible = clip.convert(clip.bounds, to: nil)
        let windowRect = CGRect(x: visible.minX,
                                y: window.frame.height - visible.maxY,
                                width: visible.width,
                                height: visible.height)
        // A card flush against either edge is on screen. Comparing raw floats
        // made a card whose sub-pixel alignment put its edge 0.4 pt outside the
        // clip bounds read as off screen, costing every such click a scroll.
        let tolerance: CGFloat = 1
        return slot.globalFrame.minX >= windowRect.minX - tolerance
            && slot.globalFrame.maxX <= windowRect.maxX + tolerance
    }

    private func scrollTo(_ id: UUID, proxy: ScrollViewProxy, animated: Bool) {
        let anchor: UnitPoint = settings.selectedClipPosition == .rightEdge ? .trailing : .center
        // Snapping is the right answer far more often than animating is: an
        // arrow key repeats faster than a tween completes, so an animated strip
        // queues a backlog of overlapping scrolls and visibly lags the
        // selection. Animation is therefore opt-in and short — it is the strip
        // re-parking itself, not a transition worth watching.
        if animated && settings.animatesStripScroll {
            withAnimation(.easeOut(duration: settings.stripScrollDuration)) {
                proxy.scrollTo(id, anchor: anchor)
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(id, anchor: anchor)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: store.searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.chromeTextTertiary)
            Text(store.searchText.isEmpty
                 ? L("Nothing copied yet")
                 : L("No matches for “%@”", store.searchText))
                .font(.system(size: 13))
                .foregroundStyle(Theme.chromeTextSecondary)
        }
    }
}

struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: RectCorner

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0
        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
}

// MARK: - AppKit probes

/// Hands the enclosing `NSScrollView` to SwiftUI.
///
/// SwiftUI's own coordinate spaces were not enough to answer "is this card on
/// screen": a preference measured with `.named(...)` reports offsets in
/// whatever space that name resolves to, and the values it produced for a
/// scrolled strip did not track the clip view's origin. The scroll view can
/// answer exactly and for free, because it already knows its bounds and its
/// content view.
struct CardSlotReporter: View {
    let id: UUID
    let side: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { publish(proxy) }
                .onChange(of: proxy.frame(in: .named(BarView.stripSpace)).origin) { _, _ in
                    publish(proxy)
                }
                // The strip's content space origin moves with the scroll
                // offset, so the reported rectangle also has to be refreshed
                // when the clip view scrolls; without this a card's recorded
                // span goes stale the moment the strip moves.
                .onReceive(NotificationCenter.default.publisher(
                    for: NSView.boundsDidChangeNotification, object: nil)
                    .receive(on: RunLoop.main)) { _ in
                        publish(proxy)
                    }
        }
    }

    /// Records both spaces. `content` answers "which card is here" once the
    /// click has already been converted to strip content coordinates, and
    /// `window` answers it directly, which is what the router prefers because
    /// it needs no conversion at all and therefore cannot drift.
    private func publish(_ proxy: GeometryProxy) {
        let content = proxy.frame(in: .named(BarView.stripSpace))
        let global = proxy.frame(in: .global)
        BarClickRouter.shared.register(id: id, contentFrame: content, globalFrame: global)
    }
}

/// The strip's own horizontal scroller.
///
/// `enclosingScrollView` finds nothing because SwiftUI's `ScrollView` does not
/// expose its `NSScrollView` to descendants, so the search walks the window
/// instead. Taking the *first* scroll view found is wrong: the window also
/// hosts narrow vertical scrollers elsewhere (a 140 pt one is the settings
/// list), and any of those answers every question with nonsense. The strip is
/// the one that is both horizontally scrollable and the widest found.
@MainActor
func findStripScrollView(in root: NSView) -> NSScrollView? {
    var best: NSScrollView?
    func visit(_ view: NSView) {
        if let scroll = view as? NSScrollView {
            let width = scroll.contentView.bounds.width
            let height = scroll.contentView.bounds.height
            if width > height, best == nil || width > best!.contentView.bounds.width {
                best = scroll
            }
        }
        for sub in view.subviews { visit(sub) }
    }
    visit(root)
    return best
}

struct StripScrollViewProbe: NSViewRepresentable {
    let onResolve: (NSScrollView?) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.onResolve = onResolve
    }

    final class ProbeView: NSView {
        var onResolve: ((NSScrollView?) -> Void)?

        /// The strip's own horizontal scroller.
        ///
        /// `enclosingScrollView` finds nothing because SwiftUI's `ScrollView`
        /// does not expose its `NSScrollView` to descendants, so the search
        /// walks the window instead. Taking the *first* scroll view found is
        /// wrong: the window also hosts narrow vertical scrollers elsewhere
        /// (a 140 pt one is the settings list), and any of those answers every
        /// question with nonsense. The strip is the one that is both
        /// horizontally scrollable and wider than it is tall.
        static func findScrollView(from view: NSView) -> NSScrollView? {
            guard let root = view.window?.contentView else { return nil }
            return findStripScrollView(in: root)
        }
        private var resolved = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !resolved, window != nil else { return }
            resolved = true
            // One turn later: at `viewDidMoveToWindow` the scroll view has been
            // attached but has not finished laying out its clip view, so the
            // document view still reports a zero-height frame.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // SwiftUI's `ScrollView` is not backed by an `NSScrollView`
                // that a descendant can reach through `enclosingScrollView`, so
                // the window's hierarchy is walked instead.
                self.onResolve?(Self.findScrollView(from: self))
            }
        }
    }
}

/// Reports one card's rectangle in the strip's content space.
///
/// `frame(in:)` is deliberately not used here. The frame this probe publishes
/// is computed from the card's own AppKit frame converted through the document
/// view, which is already in the space the scroll view scrolls, so no
/// coordinate-space guessing is involved.