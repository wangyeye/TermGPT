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
    func testSyntheticPasswordJSONRoundTripAndRemoval() throws {
        let id = UUID()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = CredentialStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertNil(try SSHPasswordStore.read(id: id, store: store))
        try SSHPasswordStore.write("fixture-password-not-real", id: id, store: store)
        XCTAssertEqual(try SSHPasswordStore.read(id: id, store: store), "fixture-password-not-real")
        try SSHPasswordStore.write("fixture-replacement-not-real", id: id, store: store)
        XCTAssertEqual(try SSHPasswordStore.read(id: id, store: store), "fixture-replacement-not-real")
        try SSHPasswordStore.remove(id: id, store: store)
        XCTAssertNil(try SSHPasswordStore.read(id: id, store: store))
    }
}

final class WebBookmarkTests: XCTestCase {
    func testWebURLValidationAndPersistence() throws {
        for address in ["https://example.com/path?q=1#section", "http://localhost:8080/"] {
            let bookmark = Bookmark(name: "Website", host: address, folderID: UUID(), connectionKind: .web)
            try bookmark.validate()
            XCTAssertThrowsError(try bookmark.arguments())
            let restored = try JSONDecoder().decode(Bookmark.self, from: JSONEncoder().encode(bookmark))
            XCTAssertEqual(restored, bookmark)
            XCTAssertEqual(try restored.webAddress().absoluteString, address)
        }
        for address in ["file:///etc/passwd", "javascript:alert(1)", "data:text/html,test", "https://" + "fixture:fixture" + "@" + "example.com", "https://", "example.com", "http://localhost:70000", "https://example.com/a b"] {
            XCTAssertThrowsError(try Bookmark(host: address, connectionKind: .web).validate(), address)
        }
    }
}

final class WebAddressBarPreferencesTests: XCTestCase {
    func testLegacyDefaultsAndExplicitVisibilityRoundTrip() throws {
        XCTAssertFalse(Preferences().showWebAddressBar)
        XCTAssertFalse(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).showWebAddressBar)
        for visible in [true, false] {
            var settings = Preferences(); settings.showWebAddressBar = visible
            let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(settings))
            XCTAssertEqual(restored.showWebAddressBar, visible)
        }
    }
}
