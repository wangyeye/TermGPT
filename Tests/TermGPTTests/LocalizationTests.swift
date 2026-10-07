import XCTest
@testable import TermGPT

final class LocalizationTests: XCTestCase {
    func testSystemLanguageAndExplicitOverrides() {
        for code in ["zh-Hans-CN", "zh-Hant-TW", "zh_CN", "ZH-HK"] {
            XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: [code]), .chinese)
        }
        for languages in [["en-GB"], ["fr-FR", "zh-Hans"], ["ja-JP"], []] {
            XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: languages), .english)
        }
        XCTAssertEqual(InterfaceLanguage.english.resolved(preferredLanguages: ["zh-Hans"]), .english)
        XCTAssertEqual(InterfaceLanguage.chinese.resolved(preferredLanguages: ["en-US"]), .chinese)
    }
    func testLayoutAndLanguageMigrateAndPersist() throws {
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.language, .system)
        XCTAssertTrue(legacy.showBookmarks); XCTAssertTrue(legacy.showChat)
        for language in InterfaceLanguage.allCases {
            for bookmarks in [true, false] {
                for chat in [true, false] {
                    var original = Preferences()
                    original.language = language; original.showBookmarks = bookmarks; original.showChat = chat
                    let saved = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(original))
                    XCTAssertEqual(saved.language, language)
                    XCTAssertEqual(saved.showBookmarks, bookmarks); XCTAssertEqual(saved.showChat, chat)
                }
            }
        }
    }
    func testLabelsAndDynamicMessagesPreserveTheirArguments() {
        XCTAssertEqual(Localization.text("设置", language: .english), "Settings")
        XCTAssertEqual(Localization.text("Settings", language: .chinese), "设置")
        XCTAssertEqual(Localization.text("设置", language: .system, preferredLanguages: ["de-DE"]), "Settings")
        let userName = "个人笔记 %@ 中文"
        let message = Localization.interpolate("删除“%@”及其本地消息记录。", [userName])
        let translated = Localization.text(message, language: .english)
        XCTAssertEqual(translated, "Delete “\(userName)” and its locally stored messages.")
        XCTAssertEqual(Localization.text(translated, language: .chinese), message)
        XCTAssertEqual(Localization.text("unrecognized terminal output", language: .chinese), "unrecognized terminal output")
        XCTAssertEqual(Localization.text("无法保存本机 JSON 配置", language: .english), "Unable to save local JSON configuration")
    }
}
