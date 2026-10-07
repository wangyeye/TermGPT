import XCTest
import SwiftTerm
@testable import TermGPT

final class PTYProbe: LocalProcessDelegate {
    let headless = HeadlessTerminal { _ in }
    var terminal: Terminal { headless.terminal }
    let outputReady: XCTestExpectation
    var received = ""
    init(_ expectation: XCTestExpectation) { outputReady = expectation }
    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {}
    func dataReceived(slice: ArraySlice<UInt8>) {
        received += String(decoding: slice, as: UTF8.self)
        terminal.feed(buffer: slice)
        if received.contains("PTY_OK") && received.contains("SIZE_DONE") { outputReady.fulfill() }
    }
    func getWindowSize() -> winsize { winsize(ws_row: 32, ws_col: 96, ws_xpixel: 0, ws_ypixel: 0) }
}
final class IntegrationTests: XCTestCase {
    func testRealPTYAndANSIOutput() async throws {
        let e = expectation(description: "PTY command output")
        e.assertForOverFulfill = false
        let probe = PTYProbe(e)
        let process = LocalProcess(delegate: probe)
        process.startProcess(executable: "/bin/zsh", args: ["-c", "test -t 0 && printf '\\033[32mPTY_OK\\033[0m\\n'; stty size; printf SIZE_DONE; sleep 1"], environment: ["TERM=xterm-256color", "PATH=/usr/bin:/bin"])
        await fulfillment(of: [e], timeout: 10)
        process.terminate()
        XCTAssertTrue(probe.received.contains("32 96"), probe.received)
        let rendered = String(decoding: probe.terminal.getBufferAsData(), as: UTF8.self)
        XCTAssertTrue(rendered.contains("PTY_OK"))
        XCTAssertFalse(rendered.contains("\u{1b}[32m"))
    }
    func testLocalStreamingProviderWhenFixtureEnabled() async throws {
        guard ProcessInfo.processInfo.environment["TERMGPT_TEST_API"] == "1" else { throw XCTSkip("Enable with TERMGPT_TEST_API=1 and scripts/mock-provider.py") }
        var p = Preferences(); p.endpoint = "http://127.0.0.1:18765/v1"; p.model = "fixture"
        let accumulator = Accumulator()
        try await OpenAIProvider(preferences: p, key: "").stream(messages: [Message(role: "user", content: "test")]) { await accumulator.append($0) }
        let result = await accumulator.text
        XCTAssertTrue(result.contains("本地接口测试通过"))
        XCTAssertTrue(result.contains("```bash\nprintf TermGPT_OK\n```"))
    }
}
actor Accumulator {
    var text = ""
    func append(_ s: String) { text += s }
}
