import XCTest
@testable import TermGPT

final class DesktopResolutionTests: XCTestCase {
    func testReadableLogicalSizeAndProtocolBounds() {
        XCTAssertEqual(DesktopResolution(size: NSSize(width: 901, height: 650))?.width, 900)
        XCTAssertEqual(DesktopResolution(size: NSSize(width: 901, height: 650))?.height, 650)
        XCTAssertEqual(DesktopResolution(size: NSSize(width: 8192, height: 4320))?.width, 4096)
        XCTAssertEqual(DesktopResolution(size: NSSize(width: 8192, height: 4320))?.height, 2160)
        XCTAssertEqual(DesktopResolution(size: NSSize(width: 100, height: 50))?.width, 200)
        XCTAssertNil(DesktopResolution(size: .zero))
        XCTAssertNil(DesktopResolution(size: NSSize(width: CGFloat.infinity, height: 600)))
    }
    func testCanvasReportsAvailableAreaChanges() {
        let canvas = DesktopCanvas(frame: NSRect(x: 0, y: 0, width: 720, height: 600))
        var changes = 0
        canvas.sizeChanged = { changes += 1 }
        canvas.setFrameSize(NSSize(width: 1000, height: 700))
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(canvas.bounds.size, NSSize(width: 1000, height: 700))
    }
}
