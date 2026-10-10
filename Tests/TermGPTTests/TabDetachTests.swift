import XCTest
@testable import TermGPT

final class TabDetachTests: XCTestCase {
    func testReorderingAndSmallPointerDriftStayAttached() {
        let strip = CGRect(x: 0, y: 0, width: 800, height: 47)
        for point in [CGPoint(x: 400, y: 20), CGPoint(x: 400, y: 70), CGPoint(x: -20, y: 20)] {
            XCTAssertFalse(TabDetachPolicy.shouldDetach(at: point, strip: strip))
        }
    }
    func testDraggingAwayInEveryDirectionDetaches() {
        let strip = CGRect(x: 0, y: 0, width: 800, height: 47)
        for point in [CGPoint(x: 400, y: 100), CGPoint(x: 400, y: -60), CGPoint(x: -60, y: 20), CGPoint(x: 860, y: 20)] {
            XCTAssertTrue(TabDetachPolicy.shouldDetach(at: point, strip: strip))
        }
        XCTAssertFalse(TabDetachPolicy.shouldDetach(at: .zero, strip: .zero))
    }
}
