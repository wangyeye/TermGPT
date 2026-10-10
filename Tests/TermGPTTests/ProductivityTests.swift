import XCTest
import AppKit
import SwiftTerm
@testable import TermGPT
final class ProductivityTests: XCTestCase {
    func testSearchUnicodeColumnsAndRegex() throws {
        let view = WorkTerminal(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.feed(text: "中文 Alpha alpha\r\nerror 123\r\n")
        let matches = try view.searchBuffer("alpha", caseSensitive: false, regex: false)
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches.first?.startColumn, 5)
        XCTAssertEqual(try view.searchBuffer("Alpha", caseSensitive: true, regex: false).count, 1)
        XCTAssertEqual(try view.searchBuffer("error \\d+", caseSensitive: false, regex: true).count, 1)
        XCTAssertThrowsError(try view.searchBuffer("[", caseSensitive: false, regex: true))
        if let match = matches.first { view.revealSearchMatch(match); XCTAssertEqual(view.getSelection(), "Alpha") }
    }
    func testSearchScrollbackRevealsHistoricalMatch() throws {
        let view = WorkTerminal(frame: NSRect(x: 0, y: 0, width: 500, height: 150))
        view.feed(text: "historical needle\r\n" + (0..<80).map { "line \($0)\r\n" }.joined())
        let match = try XCTUnwrap(view.searchBuffer("needle", caseSensitive: true, regex: false).first)
        view.revealSearchMatch(match)
        XCTAssertEqual(view.getSelection(), "needle")
        XCTAssertEqual(view.getTerminal().buffer.yDisp, 0)
    }
    func testPersistenceRetainsDuplicateTabsOrderActiveAndCommands() throws {
        let bookmark = Bookmark(name: "test", host: "example.test")
        let tabs = [RestoredTab(id: UUID(), name: "Local", bookmarkID: nil), RestoredTab(id: UUID(), name: "test", bookmarkID: bookmark.id), RestoredTab(id: UUID(), name: "test", bookmarkID: bookmark.id)]
        let command = SavedCommand(name: "Logs", folder: "Linux", command: "journalctl -n 20", note: "recent errors")
        let state = SavedState(savedCommands: [command], restoredWorkspace: RestoredWorkspace(tabs: tabs, active: tabs[1].id), bookmarks: [bookmark], folders: [], chats: [], preferences: Preferences())
        let decoded = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.restoredWorkspace?.tabs.map(\.id), tabs.map(\.id))
        XCTAssertEqual(decoded.restoredWorkspace?.active, tabs[1].id)
        XCTAssertTrue(try XCTUnwrap(decoded.savedCommands?.first).matches("linux errors"))
        XCTAssertFalse(command.matches("windows"))
    }
    func testOldWorkspaceJSONRemainsCompatible() throws {
        let old = Data("{\"tabs\":[],\"active\":null}".utf8)
        let decoded = try JSONDecoder().decode(RestoredWorkspace.self, from: old)
        XCTAssertNil(decoded.detached); XCTAssertNil(decoded.mainFrame)
    }
    func testMultiwindowLayoutRoundTrip() throws {
        let main = RestoredTab(id: UUID(), name: "Local", bookmarkID: nil)
        let detached = RestoredTab(id: UUID(), name: "Remote", bookmarkID: UUID())
        let frame = SavedWindowFrame(CGRect(x: 100, y: 200, width: 900, height: 600))
        let layout = RestoredWorkspace(tabs: [main], active: main.id, detached: [RestoredDetachedTab(tab: detached, frame: frame)], mainFrame: frame, focusedDetached: detached.id, libraries: [RestoredLibraryWindow(kind: "notepad", frame: frame)], focusedLibrary: "notepad")
        let decoded = try JSONDecoder().decode(RestoredWorkspace.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(decoded.tabs.map(\.id), [main.id])
        XCTAssertEqual(decoded.detached?.map { $0.tab.id }, [detached.id])
        XCTAssertEqual(decoded.focusedDetached, detached.id)
        XCTAssertEqual(decoded.detached?.first?.frame, frame)
        XCTAssertEqual(decoded.libraries?.first?.kind, "notepad")
        XCTAssertEqual(decoded.focusedLibrary, "notepad")
    }
    func testWindowFitsAfterMonitorRemovalAndRejectsInvalidSize() throws {
        let screen = CGRect(x: 0, y: 30, width: 1280, height: 770)
        let saved = SavedWindowFrame(CGRect(x: 2400, y: -500, width: 1900, height: 1200))
        let fitted = try XCTUnwrap(saved.fitted(to: [screen], minimum: CGSize(width: 400, height: 300)))
        XCTAssertTrue(screen.contains(fitted))
        XCTAssertEqual(fitted.size, screen.size)
        XCTAssertNil(SavedWindowFrame(CGRect(x: 0, y: 0, width: 0, height: 600)).rect)
    }
    func testTransientZeroFramePreservesTerminalHistory() throws {
        let view = WorkTerminal(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
        view.feed(text: "migration marker\r\n")
        view.frame = .zero
        view.setFrameSize(.zero)
        view.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        XCTAssertEqual(try view.searchBuffer("migration marker", caseSensitive: true, regex: false).count, 1)
    }
}
