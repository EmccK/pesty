import SwiftUI

struct BarView: View {
    let searchBridge: BarSearchFieldBridge
    @Bindable private var store = ClipboardStore.shared
    @Bindable private var settings = Settings.shared

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
        .clipShape(RoundedCorners(radius: Theme.cornerRadius, corners: [.topLeft, .topRight]))
        .ignoresSafeArea()
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
        HStack(spacing: 14) {
            // The two builds sync through different systems: the App Store build uses
            // CloudKit, everything else uses iCloud Drive. Gate the button on whichever
            // one this build actually drives.
            #if MAS
            if settings.cloudKitSync { syncButton }
            #else
            if settings.iCloudSync { syncButton }
            #endif
            searchIndicator
            PinboardTabs()
                .layoutPriority(1)
            Spacer(minLength: 8)
            if store.multiSelectedIDs.count > 1 {
                bulkDeleteButton
            }
            if store.hasUndoableDeletion {
                undoButton
            }
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
        }
        .buttonStyle(.plain)
        .help(settings.iCloudSync ? L("iCloud sync on") : L("Turn on iCloud sync"))
    }

    private var searchIndicator: some View {
        HStack(spacing: searchIsActive ? 6 : 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(searchIsActive ? Theme.chromeTextPrimary : Theme.chromeTextSecondary)
                .accessibilityHidden(true)

            // Kept mounted even in the compact state: the key monitor can
            // focus it synchronously and return the same first key event, so
            // type-anywhere search never loses a character.
            NativeBarSearchField(
                text: searchTextBinding,
                bridge: searchBridge,
                onBegin: { AppController.shared.setBarSearchEditing(true) },
                onEnd: { AppController.shared.setBarSearchEditing(false) },
                onSubmit: { AppController.shared.pasteSelected() },
                onCancel: { AppController.shared.cancelBarSearchOrHide() },
                onMoveSelection: { store.moveSelection(by: $0) }
            )
            .frame(minWidth: searchIsActive ? 120 : 0,
                   idealWidth: searchIsActive ? 180 : 0,
                   maxWidth: searchIsActive ? 260 : 0,
                   alignment: .leading)
            .opacity(searchIsActive ? 1 : 0)
            .allowsHitTesting(searchIsActive)
            .accessibilityHidden(!searchIsActive)

            if searchIsActive {
                Button {
                    AppController.shared.clearBarSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(Theme.chromeTextTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Clear search"))
            }
        }
        .padding(.horizontal, searchIsActive ? 10 : 0)
        .frame(height: 30)
        .background(searchIsActive ? Theme.fieldBG : Color.clear, in: Capsule())
        // Without this, the search field competes for space with the
        // Pinboard tabs' ScrollView in the same HStack and can get squeezed
        // below its intended width — an active query needs to keep its
        // requested width over the (infinitely flexible) tab strip.
        .layoutPriority(searchIsActive ? 2 : 0)
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

    /// On macOS 26 the glass panel extends below the visible bar so its rounded
    /// bottom corners have material to draw; that strip of extra height must not
    /// count as card room, or every card comes out one corner radius too tall.
    private static var panelBottomExtension: CGFloat {
        if #available(macOS 26.0, *) { return Theme.cornerRadius }
        return 0
    }

    private var strip: some View {
        GeometryReader { geometry in
            let side = Self.cardSide(forStripHeight: geometry.size.height,
                                     bottomExtension: Self.panelBottomExtension)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Theme.cardSpacing) {
                        ForEach(Array(store.visibleItems.enumerated()), id: \.element.id) { index, item in
                            ClipCardView(item: item,
                                         index: index,
                                         selected: store.isSelected(item.id),
                                         side: side)
                                .id(item.id)
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
                    .frame(maxHeight: .infinity, alignment: .top)
                    .animation(.spring(response: 0.34, dampingFraction: 0.8), value: store.visibleItems.count)
                    .id(Self.stripStartID)
                }
                .onChange(of: store.barPresentationToken) { _, _ in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(Self.stripStartID, anchor: .leading)
                    }
                }
                .onChange(of: store.selectedID) { _, id in
                    guard let id else { return }
                    scrollToSelected(id, proxy: proxy)
                }
                .onChange(of: settings.selectedClipPosition) { _, _ in
                    guard let id = store.selectedID else { return }
                    scrollToSelected(id, proxy: proxy)
                }
                .overlay { if store.visibleItems.isEmpty { emptyState } }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// Paste's cards are square and sized from the room the strip has: the bar
    /// can be dragged taller and the cards grow with it.
    static func cardSide(forStripHeight height: CGFloat, bottomExtension: CGFloat = 0) -> CGFloat {
        let available = height - bottomExtension - Theme.stripTopPadding - Theme.stripBottomPadding
        guard available.isFinite, available > 0 else { return Theme.cardMinSide }
        return min(Theme.cardMaxSide, max(Theme.cardMinSide, available))
    }

    /// The anchor preference decides whether the strip parks the selected
    /// card centered or against the right edge, Paste-style.
    private func scrollToSelected(_ id: UUID, proxy: ScrollViewProxy) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            proxy.scrollTo(id, anchor: settings.selectedClipPosition == .rightEdge ? .trailing : .center)
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
