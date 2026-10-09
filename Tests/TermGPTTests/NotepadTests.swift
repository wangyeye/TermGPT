import XCTest
@testable import TermGPT
final class NotepadTests: XCTestCase {
    func testNotesPreserveUnicodeMultilineAndIdentityInConfiguration() throws {
        let note = SavedNote(title: "部署记录", folder: "Home Lab", content: "中文第一行\nhttps://example.test/\n😀第二行")
        let state = SavedState(savedNotes: [note], bookmarks: [], folders: [], chats: [], preferences: Preferences())
        let decoded = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
        let restored = try XCTUnwrap(decoded.savedNotes?.first)
        XCTAssertEqual(restored.id, note.id)
        XCTAssertEqual(restored.content, note.content)
        XCTAssertEqual(restored.updatedAt, note.updatedAt)
        XCTAssertTrue(restored.matches("HOME 中文"))
        XCTAssertTrue(restored.matches("部署 第二行"))
        XCTAssertFalse(restored.matches("部署 missing"))
    }
    func testOldWorkspaceWithoutNotesLoads() throws {
        let state = SavedState(bookmarks: [], folders: [], chats: [], preferences: Preferences())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object.removeValue(forKey: "savedNotes")
        let decoded = try JSONDecoder().decode(SavedState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.savedNotes)
    }
}
