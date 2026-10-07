import XCTest
@testable import TermGPT
final class CoreTests: XCTestCase {
    func testInsertNeverIncludesExecutionControl() {
        XCTAssertTrue(Safety.insertable("ls -la"))
        for c in ["ls\nreboot", "ls\r", "\u{1b}[200~ls", "ls\u{85}rm", "ls\u{2028}rm", ""] { XCTAssertFalse(Safety.insertable(c), c) }
    }
    func testRiskReview() {
        for c in ["rm -rf /tmp/x", "reboot", "dd if=x of=y", "iptables -F", "opkg remove x", "docker system prune", "ls; reboot", "echo $(rm x)", "curl example.com", "sudo ls", "esxcli storage list"] { XCTAssertTrue(Safety.highRisk(c), c) }
        XCTAssertFalse(Safety.highRisk("ls -la"))
        XCTAssertFalse(Safety.highRisk("esxcli hardware platform get"))
    }
    func testSecretFilterIncludesMultilineKeysAndHeaders() {
        let s = "password=hello token='abc def'\nAuthorization: Bearer sk-abcdefghi\nCookie: secret=abc\n-----BEGIN OPENSSH PRIVATE KEY-----\nAAA\nBBB\n-----END OPENSSH PRIVATE KEY-----"
        let safe = Safety.redact(s)
        for secret in ["hello", "abc def", "sk-abcdefghi", "secret=abc", "AAA", "BBB"] { XCTAssertFalse(safe.contains(secret), safe) }
        XCTAssertEqual(Safety.redact("hostname gateway\nping 192.0.2.1"), "hostname gateway\nping 192.0.2.1")
    }
    func testContextRelevance() {
        XCTAssertFalse(Safety.needsTerminal("圆明园是谁烧的？", names: ["ESXi"]))
        XCTAssertFalse(Safety.needsTerminal("Mountain Lion 是哪年发布的？", names: ["ESXi"]))
        XCTAssertTrue(Safety.needsTerminal("刚才 ESXi 为什么报错？", names: ["ESXi"]))
    }
    func testSSHArgumentsDoNotInvokeShell() throws {
        let b = Bookmark(name: "Test", host: "server", port: 2222, user: "root", keyPath: "~/.ssh/key")
        let args = try b.arguments()
        XCTAssertEqual(args.last, "server")
        XCTAssertFalse(args.contains("-J"))
        XCTAssertTrue(args.contains("2222"))
        var bad = b; bad.host = "-oProxyCommand=evil"; XCTAssertThrowsError(try bad.arguments())
        bad = b; bad.port = 0; XCTAssertThrowsError(try bad.arguments())
    }
}
