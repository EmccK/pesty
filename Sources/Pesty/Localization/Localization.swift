import Foundation
import Observation

/// Loads `Localizable.strings` for the active language and hands out
/// translated text. English is the source language: a key that is missing from
/// a table is returned unchanged, so an incomplete translation degrades to
/// English instead of showing a raw identifier.
@Observable
final class Localization: @unchecked Sendable {
    static let shared = Localization()

    /// The user's choice. Changing it reloads the tables; because the property
    /// is observable, every SwiftUI view that read a translated string while
    /// building its body re-renders.
    var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            reload()
            NotificationCenter.default.post(name: .pestyLanguageDidChange, object: nil)
        }
    }

    /// The language actually in use, after resolving `.system`.
    private(set) var resolvedCode: String

    /// Locale for date, number, and relative-time formatting.
    var locale: Locale { Locale(identifier: resolvedCode) }

    var isChinese: Bool { resolvedCode == "zh-Hans" }

    private let lock = NSLock()
    private var table: [String: String] = [:]

    private init() {
        let stored = AppLanguage.persisted
        language = stored
        resolvedCode = stored.resolvedCode
        reload()
    }

    /// Look up a key. Reading `language` registers the SwiftUI observation
    /// dependency for the calling view body.
    func string(for key: String) -> String {
        _ = language
        lock.lock()
        defer { lock.unlock() }
        return table[key] ?? key
    }

    private func reload() {
        resolvedCode = language.resolvedCode
        let loaded = Self.loadTable(for: resolvedCode)
        lock.lock()
        table = loaded
        lock.unlock()
    }

    // MARK: - Loading

    private static func loadTable(for code: String) -> [String: String] {
        guard code != AppLanguage.english.rawValue,
              let url = resourceBundle?.path(forResource: "Localizable",
                                             ofType: "strings",
                                             inDirectory: nil,
                                             forLocalization: code)
        else { return [:] }
        return (NSDictionary(contentsOfFile: url) as? [String: String]) ?? [:]
    }

    /// Locates the SwiftPM resource bundle in every context Pesty runs in:
    /// `swift run`, `swift test`, the plain `.app` built by
    /// scripts/build_app.sh, and the sandboxed Mac App Store build. Unlike
    /// `Bundle.module`, a missing bundle returns nil instead of trapping, so a
    /// stripped-down build still runs in English.
    static let resourceBundle: Bundle? = {
        let name = "Pesty_Pesty.bundle"
        var candidates: [URL] = []
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        #endif
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent(name))
        }
        // Inside a test run the app module is linked into the .xctest bundle,
        // so the resource bundle sits beside that bundle rather than Bundle.main.
        if let resources = Bundle(for: ResourceBundleFinder.self).resourceURL {
            candidates.append(resources.appendingPathComponent(name))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent(name))
        candidates.append(
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources")
                .appendingPathComponent(name)
        )
        if let executable = Bundle.main.executableURL {
            candidates.append(executable.deletingLastPathComponent().appendingPathComponent(name))
        }
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            if let bundle = Bundle(url: candidate) { return bundle }
        }
        return nil
    }()
}

/// Only exists so `Bundle(for:)` can answer "which bundle holds this code?".
private final class ResourceBundleFinder {}

extension Notification.Name {
    /// Posted after the active language changes so AppKit surfaces (menus,
    /// status item, window titles) can rebuild themselves.
    static let pestyLanguageDidChange = Notification.Name("PestyLanguageDidChange")
}

// MARK: - Lookup helpers

/// Translate a key. `%ld` / `%@` placeholders in the translated text are filled
/// with `arguments` using the active locale.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let localization = Localization.shared
    let format = localization.string(for: key)
    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: localization.locale, arguments: arguments)
}

/// Translate a count-sensitive key. `one` is used for exactly 1, `many`
/// otherwise; both are ordinary keys, so a language without plural forms simply
/// maps them to the same text.
func LCount(_ count: Int, one: String, many: String) -> String {
    let localization = Localization.shared
    let format = localization.string(for: count == 1 ? one : many)
    return String(format: format, locale: localization.locale, arguments: [count])
}
