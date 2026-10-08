import XCTest
@testable import TermGPT

final class SFTPTests: XCTestCase {
    func testPacketBoundsAndAttributes() throws {
        var packet = SFTPPacket(); packet.uint(5); packet.long(0x123456789); packet.uint(0o100600)
        let entry = try packet.attributes(name: "hello")
        XCTAssertEqual(entry.size, 0x123456789); XCTAssertFalse(entry.isDirectory)
        XCTAssertThrowsError(try packet.readUInt())
        var truncated = SFTPPacket(data: Data([0, 0, 0, 10, 1]))
        XCTAssertThrowsError(try truncated.readString())
    }
    func testLocalServerListUploadDownloadAndOverwrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("termgpt-sftp-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("子目录"), withIntermediateDirectories: true)
        let source = root.appendingPathComponent("local-source")
        let payload = Data((0..<150_000).map { UInt8(truncatingIfNeeded: $0) })
        try payload.write(to: source)
        let client = SFTPConnection(localServer: URL(fileURLWithPath: "/usr/libexec/sftp-server"))
        defer { client.finish() }
        try client.start()
        let remote = root.appendingPathComponent("空格 ' $() ; file.bin").path
        var uploadBytes: UInt64 = 0
        try client.upload(source, to: remote) { bytes, total in uploadBytes = bytes; XCTAssertEqual(total, UInt64(payload.count)) }
        XCTAssertEqual(uploadBytes, UInt64(payload.count))
        let (path, entries) = try client.list(root.path)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: path)[.systemFileNumber] as? NSNumber, try FileManager.default.attributesOfItem(atPath: root.path)[.systemFileNumber] as? NSNumber)
        XCTAssertTrue(entries.contains { $0.name == "子目录" && $0.isDirectory })
        XCTAssertTrue(entries.contains { $0.name == "空格 ' $() ; file.bin" && $0.size == UInt64(payload.count) })
        let destination = root.appendingPathComponent("download")
        try Data("old".utf8).write(to: destination)
        var downloadBytes: UInt64 = 0
        try client.download(remote, to: destination) { bytes, total in downloadBytes = bytes; XCTAssertEqual(total, UInt64(payload.count)) }
        XCTAssertEqual(downloadBytes, UInt64(payload.count)); XCTAssertEqual(try Data(contentsOf: destination), payload)
        // Without replacement consent, an existing destination stays unchanged.
        XCTAssertThrowsError(try client.upload(source, to: remote) { _, _ in })
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: remote)), payload)
        try Data().write(to: source)
        try client.upload(source, to: remote, overwrite: true) { _, total in XCTAssertEqual(total, 0) }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: remote)), Data())
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasSuffix(".partial") })
        XCTAssertThrowsError(try client.list(root.appendingPathComponent("missing").path))
        // Failed download must not alter an existing local destination.
        XCTAssertThrowsError(try client.download(root.appendingPathComponent("missing").path, to: destination) { _, _ in })
        XCTAssertEqual(try Data(contentsOf: destination), payload)
    }
    func testCancelBeforeLaunchDoesNotStartAProcess() throws {
        let client = SFTPConnection(localServer: URL(fileURLWithPath: "/usr/libexec/sftp-server"))
        client.cancel(); defer { client.finish() }
        XCTAssertThrowsError(try client.start())
        XCTAssertFalse(client.process.isRunning)
    }
}
