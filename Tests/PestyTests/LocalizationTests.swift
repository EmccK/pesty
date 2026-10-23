import XCTest
@testable import Pesty

final class LocalizationTests: XCTestCase {
    override func tearDown() {
        Localization.shared.language = AppLanguage.persisted
        super.tearDown()
    }

    /// English is the source language, so a key with no table entry comes back
    /// unchanged rather than as a raw identifier.
    func testEnglishFallsBackToTheKeyItself() {
        Localization.shared.language = .english
        XCTAssertEqual(L("Copied to Clipboard"), "Copied to Clipboard")
        XCTAssertEqual(L("Copy"), "Copy")
    }

    func testChineseTableTranslatesKnownKeys() {
        Localization.shared.language = .simplifiedChinese
        XCTAssertEqual(L("Copy"), "拷贝")
        XCTAssertEqual(L("Cancel"), "取消")
        XCTAssertEqual(L("Pesty Settings"), "Pesty 设置")
    }

    func testPlaceholdersAreFilledInTheActiveLocale() {
        Localization.shared.language = .simplifiedChinese
        XCTAssertEqual(L("Paste to %@", "Safari"), "粘贴到 Safari")
        XCTAssertEqual(L("Delete %ld Clips?", 3), "删除 3 个剪贴？")
    }

    func testCountHelperPicksSingularAndPluralKeys() {
        Localization.shared.language = .simplifiedChinese
        XCTAssertEqual(LCount(1, one: "%ld clip", many: "%ld clips"), "1 个剪贴")
        XCTAssertEqual(LCount(4, one: "%ld clip", many: "%ld clips"), "4 个剪贴")
    }

    func testUnknownKeyIsReturnedUnchanged() {
        Localization.shared.language = .simplifiedChinese
        XCTAssertEqual(L("A string nobody translated"), "A string nobody translated")
    }

    /// `.system` has to resolve to one of the two bundled languages, never to a
    /// third code that has no table.
    func testSystemResolvesToABundledLanguage() {
        let resolved = AppLanguage.system.resolvedCode
        XCTAssertTrue(["en", "zh-Hans"].contains(resolved), "unexpected code \(resolved)")
    }

    func testPersistedRoundTripsThroughUserDefaults() {
        let original = UserDefaults.standard.string(forKey: AppLanguage.defaultsKey)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: AppLanguage.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.defaultsKey)
            }
        }

        UserDefaults.standard.set(AppLanguage.simplifiedChinese.rawValue, forKey: AppLanguage.defaultsKey)
        XCTAssertEqual(AppLanguage.persisted, .simplifiedChinese)

        UserDefaults.standard.set("kl_GL", forKey: AppLanguage.defaultsKey)
        XCTAssertEqual(AppLanguage.persisted, .system, "an unknown stored value falls back to following the system")
    }

    /// The table is a shipped resource; if it stops being found, every Chinese
    /// string silently turns into English.
    func testChineseTableIsBundled() {
        XCTAssertNotNil(Localization.resourceBundle, "Pesty_Pesty.bundle was not found")
        let path = Localization.resourceBundle?.path(forResource: "Localizable",
                                                    ofType: "strings",
                                                    inDirectory: nil,
                                                    forLocalization: "zh-Hans")
        XCTAssertNotNil(path, "zh-Hans.lproj/Localizable.strings is missing from the resource bundle")
        guard let path, let table = NSDictionary(contentsOfFile: path) as? [String: String] else {
            return XCTFail("the zh-Hans table could not be parsed")
        }
        XCTAssertGreaterThan(table.count, 100)
    }
}
