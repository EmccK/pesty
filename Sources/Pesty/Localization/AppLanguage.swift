import Foundation

/// Languages Pesty ships with. English is the source language, so every
/// untranslated key falls back to its English text.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let defaultsKey = "appLanguage"

    var id: String { rawValue }

    /// The language table used for lookups.
    var resolvedCode: String {
        switch self {
        case .system: Self.systemPreferredCode
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        }
    }

    /// Only English and Simplified Chinese are bundled for now; any other
    /// preferred language falls back to English.
    static var systemPreferredCode: String {
        for preferred in Locale.preferredLanguages {
            let code = preferred.lowercased()
            if code.hasPrefix("zh") { return "zh-Hans" }
            if code.hasPrefix("en") { return "en" }
        }
        return "en"
    }

    /// Language names are always written in their own language, the way macOS
    /// and most apps present them.
    var nativeName: String {
        switch self {
        case .system: Self.systemPreferredName
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    private static var systemPreferredName: String {
        systemPreferredCode == "zh-Hans" ? "简体中文" : "English"
    }

    var title: String {
        self == .system ? L("System (%@)", Self.systemPreferredName) : nativeName
    }

    /// The stored preference, read straight from `UserDefaults` so the right
    /// table is loaded before any UI exists.
    static var persisted: AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let language = AppLanguage(rawValue: raw) else { return .system }
        return language
    }
}
