import XCTest
@testable import TermGPT

final class ReplyCodeBlockTests: XCTestCase {
    func testLogsAndReferencesHaveNoTerminalActions() {
        let error = "n challenge solving failed\nOnly images are available for download\nRequested format is not available"
        for label in ["", "text", "plaintext", "log", "console", "json", "python"] {
            let block = ReplyCodeBlock(label + "\n" + error)
            XCTAssertEqual(block.content, error)
            XCTAssertFalse(block.isShellCommand)
        }
        XCTAssertFalse(ReplyCodeBlock("ls -la").isShellCommand)
    }

    func testExplicitShellCommandsRetainActionsAndCopyContent() {
        for label in ["bash", "sh", "shell", "zsh", "fish", "ksh", " Bash "] {
            let block = ReplyCodeBlock(label + "\nprintf 'hello'\n")
            XCTAssertEqual(block.content, "printf 'hello'")
            XCTAssertTrue(block.isShellCommand)
        }
        XCTAssertFalse(ReplyCodeBlock("bash\n").isShellCommand)
    }
}
