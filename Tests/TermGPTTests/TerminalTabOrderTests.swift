import XCTest
@testable import TermGPT

final class TerminalTabOrderTests: XCTestCase {
    func testCloseRightIncludesOnlyFollowingTabs() {
        let ids = (0..<4).map { _ in UUID() }
        XCTAssertEqual(TerminalTabOrder.right(of: ids[1], in: ids), Array(ids[2...]))
        XCTAssertTrue(TerminalTabOrder.right(of: ids[3], in: ids).isEmpty)
        XCTAssertTrue(TerminalTabOrder.right(of: UUID(), in: ids).isEmpty)
    }
    func testMovingBothDirectionsPreservesAllIdentities() {
        let ids = (0..<4).map { _ in UUID() }
        XCTAssertEqual(TerminalTabOrder.moving(ids[0], to: ids[2], in: ids), [ids[1], ids[2], ids[0], ids[3]])
        XCTAssertEqual(TerminalTabOrder.moving(ids[3], to: ids[1], in: ids), [ids[0], ids[3], ids[1], ids[2]])
        XCTAssertEqual(TerminalTabOrder.moving(ids[0], to: ids[0], in: ids), ids)
        XCTAssertEqual(TerminalTabOrder.moving(UUID(), to: ids[0], in: ids), ids)
    }
}
