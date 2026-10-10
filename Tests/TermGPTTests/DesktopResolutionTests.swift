import XCTest
@testable import TermGPT

final class DesktopResolutionTests: XCTestCase {
    func testDisplayModesAndRetinaLimit() throws {
        let view = NSSize(width: 1200, height: 800)
        let fit = try XCTUnwrap(DesktopResolution(size: view, backingScale: 2))
        XCTAssertEqual(fit.width, 1200); XCTAssertEqual(fit.height, 800); XCTAssertEqual(fit.desktopScale, 100)
        let retina = try XCTUnwrap(DesktopResolution(size: view, mode: .retina, backingScale: 2))
        XCTAssertEqual(retina.width, 2400); XCTAssertEqual(retina.height, 1600); XCTAssertEqual(retina.desktopScale, 200)
        let limited = try XCTUnwrap(DesktopResolution(size: NSSize(width: 2560, height: 1440), mode: .retina, backingScale: 2))
        XCTAssertEqual(limited.width, 3840); XCTAssertEqual(limited.height, 2160); XCTAssertEqual(limited.desktopScale, 150)
        let fixed = try XCTUnwrap(DesktopResolution(size: view, mode: .fixed, backingScale: 2))
        XCTAssertEqual(fixed.width, 1920); XCTAssertEqual(fixed.height, 1080); XCTAssertEqual(fixed.desktopScale, 100)
        XCTAssertEqual(fixed, DesktopResolution(size: NSSize(width: 1600, height: 1000), mode: .fixed))
    }
    func testOlderBookmarksUseFitAndSettingsRoundTrip() throws {
        var bookmark = Bookmark(name: "Fixture", host: "example.test")
        let old = try JSONDecoder().decode(Bookmark.self, from: JSONEncoder().encode(bookmark))
        XCTAssertEqual(old.desktopDisplayMode ?? .fit, .fit)
        bookmark.desktopDisplayMode = .fixed; bookmark.desktopFixedResolution = .qhd
        XCTAssertEqual(bookmark, try JSONDecoder().decode(Bookmark.self, from: JSONEncoder().encode(bookmark)))
    }
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
