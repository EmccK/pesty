import SwiftUI
import AppKit

struct SettingsView: View {
    @State private var tab: Tab = .general

    private enum Tab: CaseIterable {
        case general, privacy, about

        var title: String {
            switch self {
            case .general: L("General")
            case .privacy: L("Privacy")
            case .about: L("About")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            content
        }
        .frame(width: 520, height: 560)
    }

    /// Hand-rolled pill tabs instead of TabView, whose native tab strip draws
    /// a backing and separator that break up the window's uniform background.
    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    Text(item.title)
                        .font(.system(size: 13, weight: tab == item ? .semibold : .regular))
                        .foregroundStyle(tab == item ? .primary : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                        .background {
                            if tab == item {
                                Capsule()
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .general: GeneralSettings()
        case .privacy: PrivacySettings()
        case .about: AboutView()
        }
    }
}

private struct PrivacySettings: View {
    @Bindable private var settings = Settings.shared

    var body: some View {
        Form {
            Section(L("Excluded Apps")) {
                Text(L("Pesty will not save anything copied while one of these apps is frontmost. Copies made from a browser extension are attributed to the browser, so add that too if you use one."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.ignoredSourceAppBundleIDs.isEmpty {
                    ContentUnavailableView(L("No apps excluded"),
                                           systemImage: "hand.raised",
                                           description: Text(L("Add an app to keep its copied content out of Pesty.")))
                        .padding(.vertical, 12)
                } else {
                    ForEach(settings.ignoredSourceAppBundleIDs, id: \.self) { bundleID in
                        ignoredAppRow(bundleID)
                    }
                }

                Button { chooseApps() } label: {
                    Label(L("Add App…"), systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func ignoredAppRow(_ bundleID: String) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIconProvider.icon(forBundleID: bundleID))
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(applicationName(for: bundleID))
                    .font(.system(size: 13, weight: .medium))
                Text(bundleID)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { settings.removeIgnoredSourceApp(bundleID) } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("Allow clips from %@", applicationName(for: bundleID)))
        }
        .padding(.vertical, 4)
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.title = L("Exclude Apps from Pesty")
        panel.message = L("Pesty will ignore copied content from the apps you choose.")
        panel.prompt = L("Add Apps")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier else { continue }
            settings.addIgnoredSourceApp(bundleID)
        }
    }

    private func applicationName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else { return bundleID }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? bundleID
    }
}

private struct GeneralSettings: View {
    @Bindable private var settings = Settings.shared
    #if !MAS
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var requestedGrant = false

    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    #endif

    var body: some View {
        Form {
            Section(L("Activation")) {
                LabeledContent(L("Show Pesty")) { HotkeyRecorderView() }
            }

            HistoryRetentionSettings()

            Section(L("Quick Paste")) {
                LabeledContent(L("Paste items 1–9")) {
                    HStack(spacing: 6) {
                        modifierPicker(selection: $settings.quickPasteModifier)
                        Text("+ 1…9").foregroundStyle(.secondary)
                    }
                }
                LabeledContent(L("Paste as plain text")) {
                    modifierPicker(selection: $settings.plainTextModifier)
                }
                Text(L("Hold the plain-text modifier while using Quick Paste to strip formatting — with the defaults, ⌘⇧1 pastes the first clip as plain text. The two roles can never share a modifier; picking one that is taken swaps them."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("Behavior")) {
                #if !MAS
                Toggle(L("Paste directly into the active app"), isOn: $settings.pasteDirectly)
                #endif
                Toggle(L("Ignore passwords (concealed clips)"), isOn: $settings.ignoreConcealed)
                Toggle(L("Promote pasted clips to the top of history"), isOn: $settings.promoteOnPaste)
                Toggle(L("Play sound on paste"), isOn: $settings.playSound)
                Toggle(L("Play sound when copying from Pesty"), isOn: $settings.playSoundOnCopy)
                Toggle(L("Hide Pesty when clicking outside"), isOn: $settings.hideOnClickOutside)
                Toggle(L("Launch at login"), isOn: $settings.launchAtLogin)
                Toggle(L("Show Pesty in the menu bar"), isOn: $settings.showMenuBarIcon)
                VStack(alignment: .leading) {
                    LabeledContent(L("Bar height"), value: L("%ld pt", Int(settings.barHeight)))
                    Slider(value: $settings.barHeight, in: 300...720, step: 10)
                }
                Toggle(L("Show resize handle on the Paste Bar"), isOn: $settings.showBarResizeHandle)
                #if MAS
                Text(L("Select a clip to copy it, then press ⌘V to paste it into your app."))
                    .font(.caption).foregroundStyle(.secondary)
                #endif
            }

            Section(L("Language")) {
                Picker(L("Interface language"), selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.menu)
                Text(L("Switches Pesty's own menus and windows. Clips you copy keep their original text."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("Clip Navigation")) {
                Picker(L("Selected clip position"), selection: $settings.selectedClipPosition) {
                    ForEach(SelectedClipPosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }
                .pickerStyle(.segmented)
                Text(settings.selectedClipPosition.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            #if MAS
            Section(L("Sync")) {
                Toggle(L("Sync history with iCloud"), isOn: Binding(
                    get: { settings.cloudKitSync },
                    set: { on in
                        settings.cloudKitSync = on
                        if on { CloudSyncService.shared.enable() } else { CloudSyncService.shared.stop() }
                    }))
                Text(CloudSyncService.shared.status)
                    .font(.caption).foregroundStyle(.secondary)
            }
            #else
            Section(L("Sync")) {
                Toggle(L("Sync clipboard via iCloud Drive"), isOn: Binding(
                    get: { settings.iCloudSync },
                    set: { _ in AppController.shared.toggleICloudSync() }))
                Text(ClipboardStore.shared.iCloudAvailable
                     ? L("Keeps your history and pinboards in sync across your Macs through iCloud Drive.")
                     : L("Sign in to iCloud and enable iCloud Drive to use sync."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            #endif

            #if !MAS
            Section(L("Permissions")) {
                HStack(spacing: 10) {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityGranted ? .green : .orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Accessibility"))
                        Text(accessibilityGranted
                             ? L("Granted — direct paste is enabled.")
                             : (requestedGrant
                                ? L("Waiting… toggle Pesty on in System Settings.")
                                : L("Required to paste directly into other apps.")))
                            .font(.caption)
                            .foregroundStyle(accessibilityGranted ? .green : .secondary)
                    }
                    Spacer()
                    if !accessibilityGranted {
                        Button(L("Open Settings")) {
                            requestedGrant = true
                            PasteService.ensureAccessibility(prompt: true)
                            openAccessibilityPane()
                        }
                    } else if requestedGrant {
                        Button(L("Restart Pesty")) { AppController.restart() }
                    }
                }
            }
            #endif

            Section(L("Data")) {
                Toggle(L("Delete permanently"), isOn: $settings.deletePermanently)
                Text(L("Skips the five-minute Undo window: deleted clips are removed at once and cannot be recovered. Hold Option while deleting to skip Undo for one deletion, whatever this setting says."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L("Clear Clipboard History"), role: .destructive) {
                    ClipboardStore.shared.clearHistory()
                }
            }
        }
        .formStyle(.grouped)
        #if !MAS
        .onAppear { accessibilityGranted = AXIsProcessTrusted() }
        .onReceive(poll) { _ in
            let now = AXIsProcessTrusted()
            if now != accessibilityGranted { accessibilityGranted = now }
        }
        #endif
    }

    #if !MAS
    private func openAccessibilityPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    #endif

    private func modifierPicker(selection: Binding<Int>) -> some View {
        Picker("", selection: selection) {
            ForEach(ShortcutModifier.allCases) { modifier in
                Text("\(modifier.symbol) \(modifier.title)").tag(modifier.carbonValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minWidth: 118)
    }
}

private struct HistoryRetentionSettings: View {
    private var settings = Settings.shared
    @State private var draftMode = Settings.shared.historyRetentionMode
    @State private var draftLimit = Settings.shared.historyLimit
    @State private var draftDays = Settings.shared.historyRetentionDays
    @State private var pendingRemovalCount = 0
    @State private var confirmingChange = false
    @State private var storageBytes: Int64?

    @State private var sliderValue = HistoryRetentionPreset(nearestDays: Settings.shared.historyRetentionDays).sliderIndex
    @State private var sliderEditing = false

    private var sliderPreset: HistoryRetentionPreset { HistoryRetentionPreset(sliderIndex: sliderValue) }

    private var storageSummary: String {
        let store = ClipboardStore.shared
        let count = store.history.count + store.pinboards.reduce(0) { $0 + $1.items.count }
        let clips = LCount(count, one: "%ld clip", many: "%ld clips")
        guard let storageBytes else { return clips }
        return "\(clips) · \(ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))"
    }

    private func refreshStorageSize() async {
        let dir = ClipboardStore.shared.dataDirectory
        storageBytes = await Task.detached(priority: .utility) {
            Self.directorySize(at: dir)
        }.value
    }

    /// Walks the store directory off the main actor; images can make it
    /// large enough that a synchronous walk would hitch the Settings window.
    nonisolated private static func directorySize(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: url,
                                                              includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    var body: some View {
        Section {
            Picker(L("Limit history by"), selection: $draftMode) {
                ForEach(HistoryRetentionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            if draftMode == .itemCount {
                Stepper(value: $draftLimit, in: 50...5000, step: 50) {
                    LabeledContent(L("Keep at most"), value: L("%ld clips", draftLimit))
                }
            }
        } header: {
            Text(L("History"))
        } footer: {
            // A grouped Form lays Section body rows out on a shared label/control
            // grid that clamps a bare Slider; the footer is plain full-width content.
            if draftMode != .itemCount {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(L("Remove clips older than"))
                        Spacer()
                        Text(sliderPreset.title)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.accentColor)
                    }
                    Slider(value: $sliderValue,
                           in: 0...Double(HistoryRetentionPreset.allCases.count - 1),
                           step: 1,
                           onEditingChanged: { editing in
                               sliderEditing = editing
                               if !editing { applySliderValue() }
                           })
                    HStack(spacing: 0) {
                        ForEach(HistoryRetentionPreset.allCases) { preset in
                            Text(preset.shortTitle)
                                .font(.system(size: 10, weight: preset == sliderPreset ? .bold : .medium))
                                .foregroundStyle(preset == sliderPreset ? Color.accentColor : .secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, draftMode == .itemCount ? 0 : 4)
            LabeledContent(L("History and pinboards on disk"), value: storageSummary)
        }
        .task {
            await refreshStorageSize()
            for await _ in NotificationCenter.default.notifications(named: .pestyStoreDidSave) {
                await refreshStorageSize()
            }
        }
        .onChange(of: draftMode) { evaluateDraft() }
        .onChange(of: draftLimit) { evaluateDraft() }
        .onChange(of: draftDays) { evaluateDraft() }
        .onChange(of: sliderValue) { if !sliderEditing { applySliderValue() } }
        .alert(L("Remove %ld Clips?", pendingRemovalCount), isPresented: $confirmingChange) {
            Button(L("Remove %ld Clips", pendingRemovalCount), role: .destructive) { commit() }
            Button(L("Cancel"), role: .cancel) { revert() }
        } message: {
            Text(L("This setting removes %ld clips from history on this Mac now, and keeps pruning automatically. Pinboards are not affected, and there is no undo.", pendingRemovalCount))
        }
    }

    private var footnote: String {
        #if MAS
        L("Pruning tidies this Mac only — synced copies stay on your other devices. Pinned clips are never removed.")
        #else
        L("Pruning applies to this Mac's history. Pinned clips are never removed.")
        #endif
    }

    private func evaluateDraft() {
        let count = ClipboardStore.shared.retentionRemovalCount(
            mode: draftMode, limit: draftLimit, days: draftDays)
        if count > 0 {
            pendingRemovalCount = count
            confirmingChange = true
        } else {
            commit()
        }
    }

    private func commit() {
        settings.historyRetentionMode = draftMode
        settings.historyLimit = draftLimit
        settings.historyRetentionDays = draftDays
        ClipboardStore.shared.applyRetentionPolicy()
    }

    private func revert() {
        draftMode = settings.historyRetentionMode
        draftLimit = settings.historyLimit
        draftDays = settings.historyRetentionDays
        sliderValue = HistoryRetentionPreset(nearestDays: draftDays).sliderIndex
    }

    private func applySliderValue() {
        let days = HistoryRetentionPreset(sliderIndex: sliderValue).days
        if days != draftDays { draftDays = days }
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable().frame(width: 88, height: 88)
            Text("Pesty").font(.system(size: 26, weight: .bold))
            Text(L("Version %@", Bundle.main.appVersion))
                .font(.subheadline).foregroundStyle(.secondary)
            Text(L("A free, open-source clipboard manager for macOS.\nInspired by Paste."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            HStack(spacing: 16) {
                Link(L("GitHub"), destination: URL(string: "https://github.com/momenbasel/pesty")!)
                Link(L("Report an Issue"), destination: URL(string: "https://github.com/momenbasel/pesty/issues")!)
            }
            .padding(.top, 4)
            Button(L("Quit Pesty"), role: .destructive) {
                NSApp.terminate(nil)
            }
            .padding(.top, 8)
            Spacer()
            Text(L("MIT Licensed · Made with SwiftUI"))
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
