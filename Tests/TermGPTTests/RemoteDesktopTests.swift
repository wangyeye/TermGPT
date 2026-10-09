import XCTest
import AppKit
@testable import TermGPT
final class RemoteDesktopTests: XCTestCase {
    func testFailureClassificationDoesNotTreatOpenPortAsAuthentication() {
        XCTAssertFalse(ConnectionFailure.canRetry("RDP connection failed (0x00020009)"))
        XCTAssertFalse(ConnectionFailure.canRetry("Permission denied"))
        XCTAssertTrue(ConnectionFailure.canRetry("connection reset by peer"))
        XCTAssertEqual(ConnectionFailure.explanation("RDP error 0x00020015"), L("身份验证失败，请检查用户名、密码或私钥。"))
        XCTAssertEqual(ConnectionFailure.explanation("Unable to connect to VNC server"), L("无法建立网络连接，请检查端口、服务、防火墙及本地网络权限。"))
        XCTAssertEqual(ConnectionFailure.explanation("host key verification failed"), L("SSH 主机指纹验证失败，请核对服务器身份及 known_hosts。"))
        XCTAssertTrue(ConnectionFailure.explanation("unknown").contains(L("连接已结束。可检查网络端口及连接日志；端口可达不代表登录成功。")))
    }
    func testReconnectReplacesFailedHelperAndPreservesTabIdentity() throws {
        _ = NSApplication.shared
        var bookmark = Bookmark(name: "fixture", host: "localhost"); bookmark.connectionKind = .rdp
        let session = TerminalSession(name: "fixture", bookmark: bookmark)
        let old = RemoteDesktop(bookmark: bookmark)
        session.desktop = old; session.started = true
        let identity = session.id
        // Missing packaged helper is expected in the unit-test bundle; lifecycle reset must still occur.
        XCTAssertThrowsError(try session.reconnect(Preferences()))
        XCTAssertEqual(session.id, identity)
        XCTAssertFalse(session.desktop === old)
        session.close()
        XCTAssertNoThrow(try session.reconnect(Preferences()))
    }

    func testSmallStatusPacketArrivesWhileHelperStillRunning() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("small-packet-fixture.sh")
        try "#!/bin/sh\nread configuration\nprintf '\\000\\000\\000\\012\\002connected'\nsleep 3\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        var bookmark = Bookmark(name: "fixture", host: "localhost"); bookmark.connectionKind = .rdp
        let desktop = RemoteDesktop(bookmark: bookmark)
        defer { desktop.close() }
        let received = expectation(description: "small packet published before helper exits")
        desktop.changed = { if desktop.connected { received.fulfill() } }
        try desktop.start(helperURL: helper)
        wait(for: [received], timeout: 1.5)
    }
    func testHelperEnvironmentIncludesHomeForRDPInitialization() {
        XCTAssertEqual(RemoteDesktop.helperEnvironment["HOME"], FileManager.default.homeDirectoryForCurrentUser.path)
        XCTAssertNotNil(RemoteDesktop.helperEnvironment["TMPDIR"])
    }
    func testCertificateUsesNativeSheetAndClosesWithTab() {
        _ = NSApplication.shared
        var bookmark = Bookmark(name: "fixture", host: "desktop.example"); bookmark.connectionKind = .rdp
        let desktop = RemoteDesktop(bookmark: bookmark)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = desktop.view; desktop.active = true
        desktop.certificate = RemoteCertificate(host: "desktop.example", subject: "fixture", issuer: "fixture", fingerprint: "synthetic")
        desktop.presentCertificate()
        XCTAssertNotNil(window.attachedSheet)
        desktop.close()
        XCTAssertNil(desktop.certificate)
        window.orderOut(nil)
    }
    func testInvisibleAddressCharactersCannotReachNativeClients() {
        let address = "\u{0}desktop.example\r\n"
        XCTAssertEqual(Bookmark.cleanPastedAddress(address), "desktop.example")
        XCTAssertThrowsError(try Bookmark(name: "fixture", host: address).validate())
    }
    func testDiagnosticRedactionAndPermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bookmark = Bookmark(name: "private-label", host: "private-host", user: "private-user")
        let log = DesktopLog(bookmark: bookmark, password: "private-password", directory: directory)
        log.record("protocol", "private-password private-host private-user authentication failed")
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let contents = try String(contentsOf: file, encoding: .utf8)
        for secret in ["private-password", "private-host", "private-user", "private-label"] { XCTAssertFalse(contents.contains(secret)) }
        XCTAssertTrue(contents.contains("authentication failed"))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testClosingExitedHelperDoesNotCrashDuringQueuedWrites() throws {
        _ = NSApplication.shared
        var bookmark = Bookmark(name: "fixture", host: "localhost"); bookmark.connectionKind = .vnc
        let desktop = RemoteDesktop(bookmark: bookmark)
        try desktop.start(helperURL: URL(fileURLWithPath: "/usr/bin/true"))
        for _ in 0..<100 { desktop.send(["type": "key", "down": true]) }
        desktop.close(); desktop.close()
        let drained = expectation(description: "queued writes drain after helper exits")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertFalse(desktop.connected)
    }
    func testDesktopBookmarkRoundTripAndTerminalRejection() throws {
        for kind in [ConnectionKind.vnc, .rdp] {
            var bookmark = Bookmark(name: "desktop", host: "desktop.example")
            bookmark.connectionKind = kind; bookmark.port = kind.defaultPort; bookmark.domain = "EXAMPLE"; bookmark.clipboardSync = false
            try bookmark.validate()
            XCTAssertThrowsError(try bookmark.arguments())
            let restored = try JSONDecoder().decode(Bookmark.self, from: JSONEncoder().encode(bookmark))
            XCTAssertEqual(restored.kind, kind); XCTAssertEqual(restored.domain, "EXAMPLE"); XCTAssertFalse(restored.syncClipboard)
        }
        let legacy = Bookmark(name: "legacy", host: "ssh.example")
        XCTAssertEqual(legacy.kind, .ssh); XCTAssertTrue(legacy.syncClipboard)
    }
    func testFragmentedAndCombinedPackets() throws {
        let data = Data([0,0,0,3,2,65,66,0,0,0,1,3])
        var decoder = DesktopPacketDecoder(), packets: [DesktopPacket] = []
        for byte in data { packets += try decoder.append(Data([byte])) }
        XCTAssertEqual(packets.count, 2); XCTAssertEqual(packets[0].kind, 2); XCTAssertEqual(packets[0].data, Data("AB".utf8)); XCTAssertTrue(packets[1].data.isEmpty)
        var combined = DesktopPacketDecoder(); XCTAssertEqual(try combined.append(data).count, 2)
        for invalid in [Data([0,0,0,0]), Data([0xff,0xff,0xff,0xff])] {
            var decoder = DesktopPacketDecoder(); XCTAssertThrowsError(try decoder.append(invalid))
        }
    }
    func testFramebufferLimitsAndChannels() {
        let frame = Data([0,0,0,1,0,0,0,1,255,0,0,0])
        let image = DesktopFrame.decode(frame)
        XCTAssertEqual(image?.width, 1); XCTAssertEqual(image?.height, 1)
        let canvas = DesktopCanvas(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas; window.orderFront(nil)
        var drawnWithoutInput = false
        canvas.firstFrameDrawn = { drawnWithoutInput = true }
        canvas.image = image
        XCTAssertTrue(drawnWithoutInput)
        XCTAssertNotNil(canvas.layer?.contents)
        window.orderOut(nil)
        XCTAssertNil(DesktopFrame.decode(Data(frame.dropLast())))
        XCTAssertNil(DesktopFrame.decode(Data([0,0,32,0,0,0,0,1])))
        XCTAssertEqual(DesktopKeys.keys[117]?.0, 0x153)
        XCTAssertEqual(DesktopKeys.keys[36]?.1, 0xff0d)
    }
}
