import AppKit
import XCTest
import SwiftTerm

final class TerminalSelectionScrollTests: XCTestCase {
    @MainActor func testDraggingEdgesScrollsAndExtendsSelectionUntilRelease() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        let view = TerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 300))
        window.contentView = view
        defer { window.contentView = nil }
        view.feed(text: (0..<200).map { "line-\($0)\r\n" }.joined())
        view.scroll(toPosition: 0.4)
        let initial = view.scrollPosition
        view.mouseDown(with: try event(.leftMouseDown, view: view, x: 20, y: 150))
        view.mouseDragged(with: try event(.leftMouseDragged, view: view, x: 40, y: 1))
        let before = view.getSelection()?.count ?? 0
        await tick()
        XCTAssertGreaterThan(view.scrollPosition, initial)
        XCTAssertGreaterThan(view.getSelection()?.count ?? 0, before)
        view.mouseUp(with: try event(.leftMouseUp, view: view, x: 40, y: 1))
        let released = view.scrollPosition
        await tick()
        XCTAssertEqual(view.scrollPosition, released)
        view.mouseDown(with: try event(.leftMouseDown, view: view, x: 20, y: 150))
        view.mouseDragged(with: try event(.leftMouseDragged, view: view, x: 40, y: 299))
        await tick()
        XCTAssertLessThan(view.scrollPosition, released)
        view.mouseUp(with: try event(.leftMouseUp, view: view, x: 40, y: 299))
    }
    @MainActor func testMouseReportingDoesNotStartSelectionScrolling() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        let view = TerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 300))
        window.contentView = view
        defer { window.contentView = nil }
        view.feed(text: (0..<200).map { "line-\($0)\r\n" }.joined())
        view.scroll(toPosition: 0.4)
        view.feed(text: "\u{1b}[?1000h\u{1b}[?1002h")
        let initial = view.scrollPosition
        view.mouseDown(with: try event(.leftMouseDown, view: view, x: 20, y: 150))
        view.mouseDragged(with: try event(.leftMouseDragged, view: view, x: 40, y: 1))
        await tick()
        XCTAssertEqual(view.scrollPosition, initial)
        XCTAssertNil(view.getSelection())
    }
    @MainActor private func tick() async {
        let timer = expectation(description: "Selection timer ticks")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { timer.fulfill() }
        await fulfillment(of: [timer], timeout: 2)
    }
    @MainActor private func event(_ type: NSEvent.EventType, view: NSView, x: CGFloat, y: CGFloat) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: view.convert(NSPoint(x: x, y: y), to: nil), modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }
}
