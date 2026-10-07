import XCTest
@testable import TermGPT
final class ChatActionsTests: XCTestCase {
    func testRenameAndPersistence() throws {
        var chats = [Chat()]
        let id = chats[0].id
        XCTAssertFalse(ChatActions.rename(id, title: " \n", chats: &chats))
        XCTAssertTrue(ChatActions.rename(id, title: " 工作笔记 ", chats: &chats))
        let restored = try JSONDecoder().decode([Chat].self, from: JSONEncoder().encode(chats))
        XCTAssertEqual(restored[0].name, "工作笔记")
        XCTAssertEqual(restored[0].nameIsCustom, true)
        let legacy = try JSONDecoder().decode(Chat.self, from: Data("{\"id\":\"\(id.uuidString)\",\"name\":\"旧聊天\",\"messages\":[]}".utf8))
        XCTAssertNil(legacy.nameIsCustom)
    }
    func testDeleteSelectionAndLastChat() {
        let first = Chat(), second = Chat(), third = Chat()
        var chats = [first, second, third]
        var selected: UUID? = second.id
        XCTAssertTrue(ChatActions.delete(first.id, chats: &chats, selected: &selected))
        XCTAssertEqual(selected, second.id)
        XCTAssertTrue(ChatActions.delete(second.id, chats: &chats, selected: &selected))
        XCTAssertEqual(selected, third.id)
        XCTAssertTrue(ChatActions.delete(third.id, chats: &chats, selected: &selected))
        XCTAssertEqual(chats.count, 1)
        XCTAssertEqual(chats[0].id, selected)
        XCTAssertNotEqual(chats[0].id, third.id)
    }
}
