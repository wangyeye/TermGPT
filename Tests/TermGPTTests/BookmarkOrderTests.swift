import XCTest
@testable import TermGPT

final class BookmarkOrderTests: XCTestCase {
    func testMovingBothDirectionsAndAcrossFoldersPreservesBookmarks() throws {
        let folder = UUID()
        let first = Bookmark(name: "SSH", host: "example.com", folderID: folder)
        let second = Bookmark(name: "WEB", host: "https://example.com", folderID: folder, connectionKind: .web)
        let third = Bookmark(name: "VNC", host: "example.com", connectionKind: .vnc)
        let original = [first, second, third]
        let down = BookmarkOrder.moving(first.id, to: second.id, in: original)
        XCTAssertEqual(down.map(\.id), [second.id, first.id, third.id])
        XCTAssertEqual(BookmarkOrder.moving(first.id, to: second.id, in: down), original)
        let cross = BookmarkOrder.moving(third.id, to: second.id, in: original)
        XCTAssertEqual(cross.map(\.id), [first.id, third.id, second.id])
        XCTAssertEqual(cross[1].folderID, folder)
        XCTAssertEqual(cross[1].connectionKind, .vnc)
        XCTAssertEqual(Set(cross.map(\.id)), Set(original.map(\.id)))
        let restored = try JSONDecoder().decode([Bookmark].self, from: JSONEncoder().encode(cross))
        XCTAssertEqual(restored, cross)
        XCTAssertEqual(BookmarkOrder.moving(UUID(), to: second.id, in: original), original)
        XCTAssertEqual(BookmarkOrder.moving(first.id, to: first.id, in: original), original)
    }
    func testFolderOrderRoundTrip() throws {
        let first = BookmarkFolder(name: "A"), second = BookmarkFolder(name: "B")
        let reordered = BookmarkOrder.movingFolder(second.id, to: first.id, in: [first, second])
        XCTAssertEqual(reordered.map(\.id), [second.id, first.id])
        XCTAssertEqual(try JSONDecoder().decode([BookmarkFolder].self, from: JSONEncoder().encode(reordered)), reordered)
    }
}
