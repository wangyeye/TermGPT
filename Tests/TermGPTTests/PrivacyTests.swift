import XCTest
@testable import TermGPT
final class PrivacyTests: XCTestCase {
    func testOutgoingUsesSettingForHistoryAndCurrentContext() {
        let messages = [Message(role: "assistant", content: "token=fixture-history"), Message(role: "user", content: "查询系统运行时间\n<terminal_context>password=fixture-context</terminal_context>")]
        let raw = Safety.outgoing(messages, redact: false)
        XCTAssertEqual(raw.map(\.content), messages.map(\.content))
        XCTAssertEqual(raw.map(\.id), messages.map(\.id))
        let safe = Safety.outgoing(messages, redact: true)
        XCTAssertFalse(safe[0].content.contains("fixture-history"))
        XCTAssertFalse(safe[1].content.contains("fixture-context"))
        XCTAssertTrue(safe[1].content.contains("查询系统运行时间"))
        XCTAssertEqual(safe.map(\.id), messages.map(\.id))
    }
    func testSettingDefaultsAndPersists() throws {
        XCTAssertTrue(Preferences().redactBeforeSending)
        XCTAssertTrue(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).redactBeforeSending)
        var preferences = Preferences()
        preferences.redactBeforeSending = false
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertFalse(restored.redactBeforeSending)
    }
}
