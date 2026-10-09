import XCTest
import SwiftTerm
@testable import TermGPT

final class TerminalEnvironmentTests: XCTestCase {
    func testMissingAndCLocalesBecomeUTF8() {
        for inherited in [[:], ["LANG": "C"], ["LANG": "en_US.UTF-8", "LC_ALL": "C"], ["LANG": "C", "LC_CTYPE": "POSIX"]] {
            let result = TerminalEnvironment.make(inherited)
            XCTAssertTrue(TerminalEnvironment.isUTF8(result["LANG"]))
            XCTAssertTrue(TerminalEnvironment.isUTF8(result["LC_CTYPE"]))
            XCTAssertNil(result["LC_ALL"])
        }
    }
    func testUTF8PreferencesAndAuthenticationMessages() {
        let inherited = ["LANG": "zh_CN.UTF-8", "LC_ALL": "zh_CN.UTF-8", "PATH": "/usr/bin:/bin"]
        XCTAssertEqual(TerminalEnvironment.make(inherited)["LC_ALL"], inherited["LC_ALL"])
        let authenticated = TerminalEnvironment.make(inherited, authentication: true)
        XCTAssertNil(authenticated["LC_ALL"])
        XCTAssertEqual(authenticated["LC_CTYPE"], "zh_CN.UTF-8")
        XCTAssertEqual(authenticated["LC_MESSAGES"], "C")
        XCTAssertEqual(authenticated["PATH"], inherited["PATH"])
    }
    func testRealZshPastedChineseLine() async throws {
        let ready = expectation(description: "Zsh ready")
        let pasted = expectation(description: "Chinese line displayed without escaping")
        let text = "# 添加 Python 3.14 PATH 配置"
        let probe = UnicodePTYProbe(ready: ready, pasted: pasted, text: text)
        let process = LocalProcess(delegate: probe)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { process.terminate(); try? FileManager.default.removeItem(at: directory) }
        let environment = TerminalEnvironment.make(["LC_ALL": "C", "LANG": "C", "PATH": "/usr/bin:/bin", "HOME": directory.path], authentication: true)
        process.startProcess(executable: "/bin/zsh", args: ["-f", "-i", "-c", "PS1=''; printf '\\nUTF8_READY\\n'; vared -c -p 'input> ' line; printf '\\nRECEIVED:%s\\n' \"$line\""], environment: environment.map { "\($0.key)=\($0.value)" })
        await fulfillment(of: [ready], timeout: 10)
        process.send(data: Array(text.utf8)[...])
        await fulfillment(of: [pasted], timeout: 10)
        let displayed = String(decoding: probe.terminal.getBufferAsData(), as: UTF8.self).replacingOccurrences(of: "\u{0}", with: "")
        XCTAssertTrue(displayed.contains(text), displayed)
        process.send(data: [13][...])
        await fulfillment(of: [probe.received], timeout: 10)
        XCTAssertTrue(probe.output.contains("RECEIVED:" + text))
    }
}
private final class UnicodePTYProbe: LocalProcessDelegate {
    let headless = HeadlessTerminal { _ in }
    var terminal: Terminal { headless.terminal }
    let ready: XCTestExpectation
    let pasted: XCTestExpectation
    let received = XCTestExpectation(description: "UTF-8 received by shell")
    let text: String
    private var bytes = Data()
    var output: String { String(decoding: bytes, as: UTF8.self) }
    private var readyDone = false, pastedDone = false, receivedDone = false
    init(ready: XCTestExpectation, pasted: XCTestExpectation, text: String) { self.ready = ready; self.pasted = pasted; self.text = text }
    func getWindowSize() -> winsize { winsize(ws_row: 32, ws_col: 96, ws_xpixel: 0, ws_ypixel: 0) }
    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {}
    func dataReceived(slice: ArraySlice<UInt8>) {
        bytes.append(contentsOf: slice); terminal.feed(buffer: slice)
        if !readyDone && output.contains("input> ") { readyDone = true; ready.fulfill() }
        let displayed = String(decoding: terminal.getBufferAsData(), as: UTF8.self).replacingOccurrences(of: "\u{0}", with: "")
        if !pastedDone && displayed.contains(text) { pastedDone = true; pasted.fulfill() }
        if !receivedDone && output.contains("RECEIVED:" + text) { receivedDone = true; received.fulfill() }
    }
}
