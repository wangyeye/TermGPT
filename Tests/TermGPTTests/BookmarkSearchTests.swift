import XCTest
@testable import TermGPT
final class BookmarkSearchTests: XCTestCase {
    func testSearchMatchesAllTermsAndFolderWithoutChangingOrder() {
        let folder = BookmarkFolder(name: "生产环境")
        var bookmark = Bookmark(name: "Server Alpha", host: "example.test")
        bookmark.folderID = folder.id
        XCTAssertTrue(BookmarkSearch.matches(bookmark, query: "ALPHA ssh", folders: [folder]))
        XCTAssertTrue(BookmarkSearch.matches(bookmark, query: "生产 example", folders: [folder]))
        XCTAssertFalse(BookmarkSearch.matches(bookmark, query: "alpha rdp", folders: [folder]))
        XCTAssertTrue(BookmarkSearch.matches(bookmark, query: "  ", folders: []))
    }
    func testRecentReferencesDeduplicateAndIgnoreDeletedBookmarks() {
        let a = Bookmark(name: "a", host: "a.test"), b = Bookmark(name: "b", host: "b.test")
        XCTAssertEqual(BookmarkSearch.recent([b.id, UUID(), b.id, a.id], bookmarks: [a,b]).map(\.id), [b.id,a.id])
    }
    func testOldConfigurationLoadsWithoutRecentConnections() throws {
        let state = SavedState(bookmarks: [], folders: [], chats: [], preferences: Preferences())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object.removeValue(forKey: "recentBookmarkIDs")
        let restored = try JSONDecoder().decode(SavedState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(restored.recentBookmarkIDs)
    }
}
