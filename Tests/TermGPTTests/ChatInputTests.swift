import XCTest
import AppKit
@testable import TermGPT
final class ChatInputTests: XCTestCase {
    @MainActor func testReturnSubmitsAndOptionReturnInsertsNewline() throws {
        _ = NSApplication.shared
        let view = ChatTextView()
        view.isRichText = false
        var submissions = 0
        view.onSubmit = { submissions += 1 }
        func event(_ modifiers: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        }
        view.string = "first"
        view.setSelectedRange(NSRange(location: 5, length: 0))
        view.keyDown(with: event([]))
        XCTAssertEqual(submissions, 1)
        XCTAssertEqual(view.string, "first")
        view.keyDown(with: event(.option))
        XCTAssertEqual(submissions, 1)
        XCTAssertEqual(view.string, "first\n")
    }
    func testHelpCommandIsDirectButDestructiveCommandsAreReviewed() {
        XCTAssertFalse(Safety.highRisk("powermetrics --help"))
        XCTAssertTrue(Safety.highRisk("powermetrics --help; rm -rf /tmp/example"))
        XCTAssertTrue(Safety.highRisk("sudo powermetrics --help"))
    }
}
