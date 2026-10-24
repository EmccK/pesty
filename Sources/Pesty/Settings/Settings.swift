import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

enum ShortcutModifier: CaseIterable, Identifiable {
    case command
    case option
    case control
    case shift

    var id: Int { carbonValue }

    var carbonValue: Int {
        switch self {
        case .command: return cmdKey
        case .option: return optionKey
        case .control: return controlKey
        case .shift: return shiftKey
        }
    }

    var title: String {
        switch self {
        case .command: return L("Command")
        case .option: return L("Option")
        case .control: return L("Control")
        case .shift: return L("Shift")
        }
    }

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }

    init?(carbonValue: Int) {
        guard let modifier = Self.allCases.first(where: { $0.carbonValue == carbonValue }) else {
            return nil
        }
        self = modifier
    }
}

enum HistoryRetentionMode: String, CaseIterable, Identifiable {
    case itemCount
    case timeInterval

    var id: String { rawValue }

    var title: String {
        switch self {
        case .itemCount: return L("Number of clips")
        case .timeInterval: return L("Age of clips")
        }
    }
}

/// The discrete stops on the time-based retention slider. `historyRetentionDays`
/// stays the underlying source of truth (a raw day count, with 0 meaning
/// "forever" - never prune by age) - this just names the stops so the slider
/// can snap between them instead of offering a raw number field.
enum HistoryRetentionPreset: Int, CaseIterable, Identifiable {
    case day
    case week
    case twoWeeks
    case threeWeeks
    case month
    case twoMonths
    case threeMonths
    case sixMonths
    case year
    case forever

    var id: Int { rawValue }

    /// 0 means forever - no automatic time-based pruning.
    var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .twoWeeks: return 14
        case .threeWeeks: return 21
        case .month: return 30
        case .twoMonths: return 60
        case .threeMonths: return 90
        case .sixMonths: return 180
        case .year: return 365
        case .forever: return 0
        }
    }

    var title: String {
        switch self {
        case .day: return L("1 Day")
        case .week: return L("1 Week")
        case .twoWeeks: return L("2 Weeks")
        case .threeWeeks: return L("3 Weeks")
        case .month: return L("1 Month")
        case .twoMonths: return L("2 Months")
        case .threeMonths: return L("3 Months")
        case .sixMonths: return L("6 Months")
        case .year: return L("1 Year")
        case .forever: return L("Forever")
        }
    }

    var shortTitle: String {
        switch self {
        case .day: return L("1d")
        case .week: return L("1w")
        case .twoWeeks: return L("2w")
        case .threeWeeks: return L("3w")
        case .month: return L("1m")
        case .twoMonths: return L("2m")
        case .threeMonths: return L("3m")
        case .sixMonths: return L("6m")
        case .year: return L("1y")
        case .forever: return "∞"
        }
    }

    var sliderIndex: Double { Double(rawValue) }

    /// Snaps an arbitrary day count (including ones from before this preset
    /// set existed) to its nearest stop, so old UserDefaults values still
    /// land on a sensible position on the slider.
    init(nearestDays days: Int) {
        self = Self.allCases.min(by: { abs($0.days - days) < abs($1.days - days) }) ?? .month
    }

    init(sliderIndex: Double) {
        let index = min(Self.allCases.count - 1, max(0, Int(sliderIndex.rounded())))
        self = Self.allCases[index]
    }
}

/// Where the strip puts the clip the user is on.
///
/// The two anchor modes answer "where does the selection sit"; `scrollPolicy`
/// below answers the separate question of whether reaching a clip should move
/// the strip at all. Clicking a card near the edge and having the whole row
/// slide under the pointer is the behaviour `.center` produces by default.
enum SelectedClipPosition: Int, CaseIterable, Identifiable {
    case center
    case rightEdge
    /// Never move the strip for a selection that is already on screen. The
    /// strip scrolls only when the clip is genuinely out of view, which keeps
    /// the row still under the pointer while the user is clicking through it.
    case keepVisible

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .center: L("Center")
        case .rightEdge: L("Right edge")
        case .keepVisible: L("Don't scroll")
        }
    }

    var detail: String {
        switch self {
        case .center:
            L("Keep the selected clip centered with surrounding context visible.")
        case .rightEdge:
            L("Place the selected clip at the far right, like Paste.")
        case .keepVisible:
            L("Leave the strip where it is while you click. It only scrolls when a clip is out of view.")
        }
    }

    /// Whether reaching this clip should move the strip even when the clip is
    /// already fully on screen.
    var centersOnEverySelection: Bool {
        self != .keepVisible
    }
}

@Observable
@MainActor
final class Settings {
    static let shared = Settings()

    @ObservationIgnored private let d = UserDefaults.standard
    @ObservationIgnored private var isLoaded = false

    enum Keys {
        static let historyLimit = "historyLimit"
        static let historyRetentionMode = "historyRetentionMode"
        static let historyRetentionDays = "historyRetentionDays"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let quickPasteModifier = "quickPasteModifier"
        static let plainTextModifier = "plainTextModifier"
        static let launchAtLogin = "launchAtLogin"
        static let hideOnClickOutside = "hideOnClickOutside"
        static let pasteDirectly = "pasteDirectly"
        static let playSound = "playSound"
        static let playSoundOnCopy = "playSoundOnCopy"
        static let promoteOnPaste = "promoteOnPaste"
        static let ignoreConcealed = "ignoreConcealed"
        static let deletePermanently = "deletePermanently"
        static let ignoredSourceAppBundleIDs = "ignoredSourceAppBundleIDs"
        static let barHeight = "barHeight"
        static let showBarResizeHandle = "showBarResizeHandle"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let onboarded = "onboarded"
        static let iCloudSync = "iCloudSync"
        static let cloudKitSync = "cloudKitSync"
        static let selectedClipPosition = "selectedClipPosition"
        static let animatesStripScroll = "animatesStripScroll"
        static let stripScrollDuration = "stripScrollDuration"
        static let appLanguage = "appLanguage"
    }

    var historyLimit: Int {
        didSet {
            guard isLoaded else { return }
            if historyLimit < 20 { historyLimit = 20; return }
            d.set(historyLimit, forKey: Keys.historyLimit)
        }
    }

    var historyRetentionMode: HistoryRetentionMode {
        didSet {
            guard isLoaded else { return }
            d.set(historyRetentionMode.rawValue, forKey: Keys.historyRetentionMode)
        }
    }

    /// A raw day count for time-based pruning; 0 means forever (no automatic
    /// pruning by age). See `HistoryRetentionPreset` for the named stops the
    /// Settings slider snaps this to.
    var historyRetentionDays: Int {
        didSet {
            guard isLoaded else { return }
            if historyRetentionDays < 0 { historyRetentionDays = 0; return }
            d.set(historyRetentionDays, forKey: Keys.historyRetentionDays)
        }
    }

    var hotkeyKeyCode: Int {
        didSet { guard isLoaded else { return }
            d.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode); HotKeyCenter.shared.reload() }
    }

    var hotkeyModifiers: Int {
        didSet { guard isLoaded else { return }
            d.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers); HotKeyCenter.shared.reload() }
    }

    var quickPasteModifier: Int {
        didSet {
            guard isLoaded else { return }
            if quickPasteModifier == plainTextModifier { plainTextModifier = oldValue }
            d.set(quickPasteModifier, forKey: Keys.quickPasteModifier)
        }
    }

    var plainTextModifier: Int {
        didSet {
            guard isLoaded else { return }
            if plainTextModifier == quickPasteModifier { quickPasteModifier = oldValue }
            d.set(plainTextModifier, forKey: Keys.plainTextModifier)
        }
    }

    var launchAtLogin: Bool {
        didSet { guard isLoaded else { return }
            d.set(launchAtLogin, forKey: Keys.launchAtLogin); LaunchAtLogin.set(enabled: launchAtLogin) }
    }

    var hideOnClickOutside: Bool {
        didSet { guard isLoaded else { return }; d.set(hideOnClickOutside, forKey: Keys.hideOnClickOutside) }
    }

    var pasteDirectly: Bool {
        didSet { guard isLoaded else { return }; d.set(pasteDirectly, forKey: Keys.pasteDirectly) }
    }

    var playSound: Bool {
        didSet { guard isLoaded else { return }; d.set(playSound, forKey: Keys.playSound) }
    }

    var playSoundOnCopy: Bool {
        didSet { guard isLoaded else { return }; d.set(playSoundOnCopy, forKey: Keys.playSoundOnCopy) }
    }

    /// Pasting a clip moves it to the front of history the way copying it
    /// from the bar does. Off by default: history has always been ordered by
    /// when a clip was copied, and the quick-paste numbers would shift on
    /// every paste.
    var promoteOnPaste: Bool {
        didSet { guard isLoaded else { return }; d.set(promoteOnPaste, forKey: Keys.promoteOnPaste) }
    }

    var ignoreConcealed: Bool {
        didSet { guard isLoaded else { return }; d.set(ignoreConcealed, forKey: Keys.ignoreConcealed) }
    }

    /// Deleted clips are purged at once instead of staying restorable with
    /// Command-Z for five minutes.
    var deletePermanently: Bool {
        didSet { guard isLoaded else { return }; d.set(deletePermanently, forKey: Keys.deletePermanently) }
    }

    /// Applications whose copied content should never be recorded in history.
    /// Store bundle identifiers rather than paths so the choice continues to work
    /// when an app is updated or moved.
    private(set) var ignoredSourceAppBundleIDs: [String] {
        didSet { guard isLoaded else { return }; d.set(ignoredSourceAppBundleIDs, forKey: Keys.ignoredSourceAppBundleIDs) }
    }

    var barHeight: Double {
        didSet {
            guard isLoaded else { return }
            let normalized = BarResizeGeometry.normalizedPersistedHeight(barHeight)
            if normalized != barHeight { barHeight = normalized; return }
            d.set(barHeight, forKey: Keys.barHeight)
        }
    }

    var showBarResizeHandle: Bool {
        didSet {
            guard isLoaded else { return }
            d.set(showBarResizeHandle, forKey: Keys.showBarResizeHandle)
        }
    }

    var showMenuBarIcon: Bool {
        didSet {
            guard isLoaded else { return }
            d.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon)
            AppController.shared.setMenuBarIconVisible(showMenuBarIcon)
        }
    }

    var onboarded: Bool {
        didSet { guard isLoaded else { return }; d.set(onboarded, forKey: Keys.onboarded) }
    }

    var iCloudSync: Bool {
        didSet { guard isLoaded else { return }; d.set(iCloudSync, forKey: Keys.iCloudSync) }
    }

    var cloudKitSync: Bool {
        didSet { guard isLoaded else { return }; d.set(cloudKitSync, forKey: Keys.cloudKitSync) }
    }

    var selectedClipPosition: SelectedClipPosition {
        didSet { guard isLoaded else { return }; d.set(selectedClipPosition.rawValue, forKey: Keys.selectedClipPosition) }
    }

    /// Whether a jump to a distant clip is animated. Arrowing between
    /// neighbours always snaps regardless: a 0.2 s tween per step cannot finish
    /// before the next key repeat, and the queue that builds up is what makes
    /// keyboard navigation feel like it is dragging.
    var animatesStripScroll: Bool {
        didSet { guard isLoaded else { return }; d.set(animatesStripScroll, forKey: Keys.animatesStripScroll) }
    }

    /// How long the animated jump takes. Short on purpose: this is the strip
    /// re-parking itself, not a transition the user asked to watch.
    var stripScrollDuration: Double {
        didSet {
            guard isLoaded else { return }
            let clamped = min(0.6, max(0.05, stripScrollDuration))
            if clamped != stripScrollDuration { stripScrollDuration = clamped; return }
            d.set(clamped, forKey: Keys.stripScrollDuration)
        }
    }

    /// The interface language. Written straight through to `Localization`, which
    /// swaps the active table and notifies AppKit surfaces to rebuild.
    var appLanguage: AppLanguage {
        didSet {
            guard isLoaded else { return }
            d.set(appLanguage.rawValue, forKey: Keys.appLanguage)
            Localization.shared.language = appLanguage
        }
    }

    private init() {
        d.register(defaults: [
            Keys.historyLimit: 500,
            Keys.historyRetentionMode: HistoryRetentionMode.itemCount.rawValue,
            Keys.historyRetentionDays: 30,
            Keys.hotkeyKeyCode: kVK_ANSI_V,
            Keys.hotkeyModifiers: cmdKey | shiftKey,
            Keys.quickPasteModifier: cmdKey,
            Keys.plainTextModifier: shiftKey,
            Keys.launchAtLogin: false,
            Keys.hideOnClickOutside: true,
            Keys.pasteDirectly: true,
            Keys.playSound: false,
            // Off by default, matching the paste sound: existing users
            // shouldn't gain a new audible behavior from an update.
            Keys.playSoundOnCopy: false,
            Keys.promoteOnPaste: false,
            Keys.ignoreConcealed: true,
            Keys.deletePermanently: false,
            Keys.ignoredSourceAppBundleIDs: [],
            Keys.barHeight: BarResizeGeometry.defaultHeight,
            Keys.showBarResizeHandle: false,
            Keys.showMenuBarIcon: true,
            Keys.onboarded: false,
            Keys.iCloudSync: false,
            Keys.cloudKitSync: true,
            Keys.selectedClipPosition: SelectedClipPosition.keepVisible.rawValue,
            Keys.animatesStripScroll: true,
            Keys.stripScrollDuration: 0.16,
            Keys.appLanguage: AppLanguage.system.rawValue
        ])
        historyLimit = d.integer(forKey: Keys.historyLimit)
        historyRetentionMode = HistoryRetentionMode(rawValue: d.string(forKey: Keys.historyRetentionMode) ?? "")
            ?? .itemCount
        historyRetentionDays = max(0, d.integer(forKey: Keys.historyRetentionDays))
        hotkeyKeyCode = d.integer(forKey: Keys.hotkeyKeyCode)
        hotkeyModifiers = d.integer(forKey: Keys.hotkeyModifiers)
        quickPasteModifier = d.integer(forKey: Keys.quickPasteModifier)
        plainTextModifier = d.integer(forKey: Keys.plainTextModifier)
        launchAtLogin = d.bool(forKey: Keys.launchAtLogin)
        hideOnClickOutside = d.bool(forKey: Keys.hideOnClickOutside)
        pasteDirectly = d.bool(forKey: Keys.pasteDirectly)
        playSound = d.bool(forKey: Keys.playSound)
        playSoundOnCopy = d.bool(forKey: Keys.playSoundOnCopy)
        promoteOnPaste = d.bool(forKey: Keys.promoteOnPaste)
        ignoreConcealed = d.bool(forKey: Keys.ignoreConcealed)
        deletePermanently = d.bool(forKey: Keys.deletePermanently)
        ignoredSourceAppBundleIDs = (d.stringArray(forKey: Keys.ignoredSourceAppBundleIDs) ?? [])
            .filter { !$0.isEmpty }
        let storedBarHeight = d.double(forKey: Keys.barHeight)
        let normalizedBarHeight = BarResizeGeometry.normalizedPersistedHeight(storedBarHeight)
        barHeight = normalizedBarHeight
        showBarResizeHandle = d.bool(forKey: Keys.showBarResizeHandle)
        showMenuBarIcon = d.bool(forKey: Keys.showMenuBarIcon)
        onboarded = d.bool(forKey: Keys.onboarded)
        iCloudSync = d.bool(forKey: Keys.iCloudSync)
        cloudKitSync = d.bool(forKey: Keys.cloudKitSync)
        selectedClipPosition = SelectedClipPosition(rawValue: d.integer(forKey: Keys.selectedClipPosition)) ?? .keepVisible
        animatesStripScroll = d.object(forKey: Keys.animatesStripScroll) as? Bool ?? true
        stripScrollDuration = d.object(forKey: Keys.stripScrollDuration) as? Double ?? 0.16
        appLanguage = AppLanguage.persisted
        isLoaded = true
        if normalizedBarHeight != storedBarHeight {
            d.set(normalizedBarHeight, forKey: Keys.barHeight)
        }
    }

    var hotkeyDisplay: String {
        HotKeyCenter.describe(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    var quickPasteModifierDisplay: String {
        ShortcutModifier(carbonValue: quickPasteModifier)?.symbol ?? "⌘"
    }

    func isIgnoringSourceApp(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return ignoredSourceAppBundleIDs.contains(bundleID)
    }

    func addIgnoredSourceApp(_ bundleID: String) {
        guard !bundleID.isEmpty, !ignoredSourceAppBundleIDs.contains(bundleID) else { return }
        ignoredSourceAppBundleIDs.append(bundleID)
        ignoredSourceAppBundleIDs.sort()
    }

    func removeIgnoredSourceApp(_ bundleID: String) {
        ignoredSourceAppBundleIDs.removeAll { $0 == bundleID }
    }
}
