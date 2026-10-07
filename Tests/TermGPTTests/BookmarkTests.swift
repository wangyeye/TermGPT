import XCTest
@testable import TermGPT
final class BookmarkTests: XCTestCase {
    func testLegacyBookmarkAndStateMigration() throws {
        let bookmark = try JSONDecoder().decode(Bookmark.self, from: Data(#"{"id":"11111111-1111-1111-1111-111111111111","name":"legacy","host":"server.example","port":22,"user":"","keyPath":"","jump":"ignored.example","notes":""}"#.utf8))
        XCTAssertNil(bookmark.folderID)
        XCTAssertNil(bookmark.authentication)
        XCTAssertFalse(try bookmark.arguments().contains("-J"))
        let raw = #"{"bookmarks":[],"chats":[],"preferences":{}}"#
        let state = try JSONDecoder().decode(SavedState.self, from: Data(raw.utf8))
        XCTAssertNil(state.folders)
    }
    func testAuthenticationArgumentsAndFolderRoundTrip() throws {
        let folder = BookmarkFolder(name: "开发")
        var bookmark = Bookmark(name: "test", host: "server.example")
        bookmark.folderID = folder.id; bookmark.authentication = .password
        let args = try bookmark.arguments()
        XCTAssertTrue(args.contains("PubkeyAuthentication=no"))
        XCTAssertTrue(args.contains("ProxyJump=none"))
        XCTAssertFalse(args.contains("-J"))
        let encoded = try JSONEncoder().encode(bookmark)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("fixture-password"))
        let restored = try JSONDecoder().decode(Bookmark.self, from: encoded)
        XCTAssertEqual(restored.folderID, folder.id)
        XCTAssertEqual(restored.authentication, .password)
        bookmark.authentication = .key; bookmark.keyPath = "~/.ssh/test-key"
        XCTAssertTrue(try bookmark.arguments().contains("-i"))
    }
    func testSyntheticPasswordKeychainRoundTripAndRemoval() throws {
        let id = UUID()
        defer { try? SSHPasswordStore.remove(id: id) }
        XCTAssertNil(try SSHPasswordStore.read(id: id))
        try SSHPasswordStore.write("fixture-password-not-real", id: id)
        XCTAssertEqual(try SSHPasswordStore.read(id: id), "fixture-password-not-real")
        try SSHPasswordStore.write("fixture-replacement-not-real", id: id)
        XCTAssertEqual(try SSHPasswordStore.read(id: id), "fixture-replacement-not-real")
        try SSHPasswordStore.remove(id: id)
        XCTAssertNil(try SSHPasswordStore.read(id: id))
    }
}
