import XCTest
@testable import TermGPT
final class RemoteDesktopTests: XCTestCase {
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
        XCTAssertNil(DesktopFrame.decode(Data(frame.dropLast())))
        XCTAssertNil(DesktopFrame.decode(Data([0,0,32,0,0,0,0,1])))
        XCTAssertEqual(DesktopKeys.keys[117]?.0, 0x153)
        XCTAssertEqual(DesktopKeys.keys[36]?.1, 0xff0d)
    }
}
