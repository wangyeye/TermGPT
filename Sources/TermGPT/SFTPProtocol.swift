import Foundation
import Darwin

struct SFTPEntry: Identifiable {
    var id: String { name }
    let name: String
    let size: UInt64?
    let permissions: UInt32?
    var isDirectory: Bool { (permissions ?? 0) & 0o170000 == 0o040000 }
    var isLink: Bool { (permissions ?? 0) & 0o170000 == 0o120000 }
}
struct SFTPPacket {
    var data = Data()
    var cursor = 0
    mutating func byte(_ value: UInt8) { data.append(value) }
    mutating func uint(_ value: UInt32) { data.append(contentsOf: (0..<4).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
    mutating func long(_ value: UInt64) { uint(UInt32(truncatingIfNeeded: value >> 32)); uint(UInt32(truncatingIfNeeded: value)) }
    mutating func string(_ value: Data) { uint(UInt32(value.count)); data.append(value) }
    mutating func string(_ value: String) { string(Data(value.utf8)) }
    mutating func read(_ count: Int) throws -> Data {
        guard count >= 0, cursor <= data.count, count <= data.count - cursor else { throw AppError.message("SFTP 响应格式无效") }
        defer { cursor += count }; return data.subdata(in: cursor..<cursor + count)
    }
    mutating func readByte() throws -> UInt8 { try read(1)[0] }
    mutating func readUInt() throws -> UInt32 { try read(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } }
    mutating func readLong() throws -> UInt64 { let high = try readUInt(); return (UInt64(high) << 32) | UInt64(try readUInt()) }
    mutating func readString() throws -> Data { let length = try readUInt(); return try read(Int(length)) }
    mutating func readText() throws -> String {
        guard let text = String(data: try readString(), encoding: .utf8) else { throw AppError.message("SFTP 文件名不是有效的 UTF-8") }; return text
    }
    mutating func attributes(name: String) throws -> SFTPEntry {
        let flags = try readUInt()
        guard flags & ~UInt32(0x8000000f) == 0 else { throw AppError.message("SFTP 响应格式无效") }
        let size = flags & 1 != 0 ? try readLong() : nil
        if flags & 2 != 0 { _ = try read(8) }
        let permissions = flags & 4 != 0 ? try readUInt() : nil
        if flags & 8 != 0 { _ = try read(8) }
        if flags & 0x80000000 != 0 {
            let count = try readUInt(); guard count < 10000 else { throw AppError.message("SFTP 响应格式无效") }
            for _ in 0..<count { _ = try readString(); _ = try readString() }
        }
        return SFTPEntry(name: name, size: size, permissions: permissions)
    }
}

/// Version 3 packets over a system OpenSSH subsystem, never shell command text.
final class SFTPConnection: @unchecked Sendable {
    let process = Process()
    private let input = Pipe(), output = Pipe(), errors = Pipe()
    private let lock = NSLock()
    private var stopped = false
    private var timedOut = false
    private var diagnostic = Data()
    private var sequence: UInt32 = 0
    private var posixRename = false
    init(bookmark: Bookmark, helper: URL, language: String) throws {
        var args = try bookmark.arguments()
        args.removeFirst() // No PTY: stdout is the binary protocol.
        args.removeLast()
        args += ["-T", "-o", "ConnectTimeout=15", "-o", "ServerAliveCountMax=2", "-o", "StrictHostKeyChecking=ask", "-s", bookmark.host, "sftp"]
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh"); process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["SSH_ASKPASS"] = helper.path; env["SSH_ASKPASS_REQUIRE"] = "force"
        env["DISPLAY"] = "TermGPT"; env["TERMGPT_SSH_BOOKMARK_ID"] = bookmark.id.uuidString
        env["TERMGPT_UI_LANGUAGE"] = language; env["TERMGPT_SFTP_AUTH"] = "1"; env["LC_ALL"] = "C"
        process.environment = env
        configurePipes()
    }
    // Local protocol server fixture for integration tests, not exposed in the UI.
    init(localServer: URL) {
        process.executableURL = localServer
        configurePipes()
    }
    private func configurePipes() {
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            self.lock.lock(); self.diagnostic.append(chunk); self.diagnostic = Data(self.diagnostic.suffix(8192)); self.lock.unlock()
        }
    }
    func start() throws {
        lock.lock(); let cancelled = stopped; lock.unlock()
        guard !cancelled else { throw CancellationError() }
        try process.run()
        lock.lock(); let cancelledAfterLaunch = stopped; lock.unlock()
        if cancelledAfterLaunch { cancel(); throw CancellationError() }
        var initPacket = SFTPPacket(); initPacket.uint(3); try send(1, initPacket.data)
        var response = try receive()
        guard try response.readByte() == 2, try response.readUInt() == 3 else { throw AppError.message("服务器不支持 SFTP v3") }
        while response.cursor < response.data.count {
            let name = try response.readText(), version = try response.readText()
            if name == "posix-rename@openssh.com", version == "1" { posixRename = true }
        }
    }
    func cancel() {
        lock.lock(); stopped = true; lock.unlock()
        if process.isRunning { process.terminate() }
    }
    func finish() {
        errors.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
    private func send(_ type: UInt8, _ body: Data) throws {
        lock.lock(); let cancelled = stopped; lock.unlock()
        if cancelled { throw CancellationError() }
        var packet = SFTPPacket(); packet.uint(UInt32(body.count + 1)); packet.byte(type); packet.data.append(body)
        try input.fileHandleForWriting.write(contentsOf: packet.data)
    }
    private func exact(_ count: Int) throws -> Data {
        var data = Data()
        while data.count < count {
            guard let part = try output.fileHandleForReading.read(upToCount: count - data.count), !part.isEmpty else {
                lock.lock(); let cancelled = stopped; let detail = String(decoding: diagnostic, as: UTF8.self); lock.unlock()
                if cancelled { throw CancellationError() }
                lock.lock(); let timeout = timedOut; lock.unlock()
                if timeout { throw AppError.message("SFTP 响应超时，请检查连接后重试") }
                throw AppError.message(L("SFTP 连接中断：%@", detail.isEmpty ? L("服务器未返回数据") : detail))
            }
            data.append(part)
        }
        return data
    }
    private func receive() throws -> SFTPPacket {
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.timedOut = true; self.lock.unlock()
            if self.process.isRunning { self.process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: timeout)
        defer { timeout.cancel() }
        var header = SFTPPacket(data: try exact(4)); let count = try header.readUInt()
        guard count > 0, count <= 4 * 1024 * 1024 else { throw AppError.message("SFTP 响应格式无效") }
        return SFTPPacket(data: try exact(Int(count)))
    }
    private func request(_ type: UInt8, _ body: SFTPPacket) throws -> (UInt8, SFTPPacket) {
        sequence &+= 1
        var packet = SFTPPacket(); packet.uint(sequence); packet.data.append(body.data); try send(type, packet.data)
        var response = try receive(); let kind = try response.readByte()
        guard try response.readUInt() == sequence else { throw AppError.message("SFTP 响应格式无效") }
        return (kind, response)
    }
    private func status(_ packet: SFTPPacket, allowEOF: Bool = false) throws -> Bool {
        var packet = packet; let code = try packet.readUInt(); let description = try packet.readText()
        if code == 0 { return true }
        if code == 1 && allowEOF { return false }
        throw AppError.message(L("SFTP 操作失败（%@）：%@", String(code), description))
    }
    private func handle(_ type: UInt8, _ body: SFTPPacket) throws -> Data {
        let (kind, response) = try request(type, body)
        if kind == 101 { _ = try status(response) }
        guard kind == 102 else { throw AppError.message("SFTP 响应格式无效") }
        var packet = response; return try packet.readString()
    }
    private func close(_ handle: Data) throws {
        var body = SFTPPacket(); body.string(handle); let (kind, packet) = try request(4, body)
        guard kind == 101 else { throw AppError.message("SFTP 响应格式无效") }; _ = try status(packet)
    }
    static func path(_ directory: String, _ name: String) -> String { directory == "/" ? "/" + name : directory + "/" + name }
    func list(_ path: String) throws -> (String, [SFTPEntry]) {
        var body = SFTPPacket(); body.string(path)
        let (kind, response) = try request(16, body)
        if kind == 101 { _ = try status(response) }
        guard kind == 104 else { throw AppError.message("SFTP 响应格式无效") }
        var canonicalPacket = response
        guard try canonicalPacket.readUInt() > 0 else { throw AppError.message("SFTP 响应格式无效") }
        let canonical = try canonicalPacket.readText()
        body = SFTPPacket(); body.string(canonical); let directory = try handle(11, body)
        defer { try? close(directory) }
        var entries: [SFTPEntry] = []
        while true {
            body = SFTPPacket(); body.string(directory)
            let (kind, response) = try request(12, body)
            if kind == 101 { if try !status(response, allowEOF: true) { break }; throw AppError.message("SFTP 响应格式无效") }
            guard kind == 104 else { throw AppError.message("SFTP 响应格式无效") }
            var names = response; let count = try names.readUInt()
            guard count > 0, count <= 100000, entries.count < 200000 else { throw AppError.message("SFTP 目录过大") }
            for _ in 0..<count {
                let name = try names.readText(); _ = try names.readString()
                let entry = try names.attributes(name: name)
                if name != "." && name != "..", !name.contains("/"), !name.contains("\0") { entries.append(entry) }
            }
        }
        return (canonical, entries.sorted { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
    func download(_ remote: String, to local: URL, progress: (UInt64, UInt64?) -> Void) throws {
        var body = SFTPPacket(); body.string(remote); body.uint(1); body.uint(0)
        let file = try handle(3, body); defer { try? close(file) }
        body = SFTPPacket(); body.string(file); let (kind, attrs) = try request(8, body)
        if kind == 101 { _ = try status(attrs) }
        guard kind == 105 else { throw AppError.message("SFTP 响应格式无效") }
        var attributes = attrs; let total = try attributes.attributes(name: remote).size
        let temporary = local.deletingLastPathComponent().appendingPathComponent(".termgpt-" + UUID().uuidString + ".partial")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw AppError.message("无法创建下载文件") }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let destination = try FileHandle(forWritingTo: temporary); defer { try? destination.close() }
        var offset: UInt64 = 0; progress(offset, total)
        while true {
            body = SFTPPacket(); body.string(file); body.long(offset); body.uint(32768)
            let (kind, response) = try request(5, body)
            if kind == 101 { if try !status(response, allowEOF: true) { break }; throw AppError.message("SFTP 响应格式无效") }
            guard kind == 103 else { throw AppError.message("SFTP 响应格式无效") }
            var packet = response; let data = try packet.readString()
            guard !data.isEmpty, data.count <= 32768 else { throw AppError.message("SFTP 响应格式无效") }
            try destination.write(contentsOf: data); offset += UInt64(data.count); progress(offset, total)
        }
        if let total, offset != total { throw AppError.message("下载文件大小发生变化，请重新下载") }
        try destination.synchronize(); try destination.close()
        guard rename(temporary.path, local.path) == 0 else { throw AppError.message("无法保存下载文件") }
    }
    func upload(_ local: URL, to remote: String, overwrite: Bool = false, progress: (UInt64, UInt64?) -> Void) throws {
        // Stage beside the destination: interrupted uploads never truncate its contents.
        let temporary = remote + ".termgpt-" + UUID().uuidString + ".partial"
        let source = try FileHandle(forReadingFrom: local); defer { try? source.close() }
        let total = try source.seekToEnd(); try source.seek(toOffset: 0)
        var body = SFTPPacket(); body.string(temporary); body.uint(2 | 8 | 16 | 32); body.uint(4); body.uint(0o600)
        let file = try handle(3, body)
        var offset: UInt64 = 0
        var committed = false
        defer {
            if !committed {
                try? close(file)
                var remove = SFTPPacket(); remove.string(temporary); _ = try? request(13, remove)
            }
        }
        progress(0, total)
        while let data = try source.read(upToCount: 32768), !data.isEmpty {
            body = SFTPPacket(); body.string(file); body.long(offset); body.string(data)
            let (kind, response) = try request(6, body)
            guard kind == 101 else { throw AppError.message("SFTP 响应格式无效") }; _ = try status(response)
            offset += UInt64(data.count); progress(offset, total)
        }
        guard offset == total else { throw AppError.message("上传文件大小发生变化，请重新上传") }
        try close(file)
        body = SFTPPacket()
        let atomicReplace = overwrite && posixRename
        if atomicReplace { body.string("posix-rename@openssh.com") }
        body.string(temporary); body.string(remote)
        let (kind, response) = try request(atomicReplace ? 200 : 18, body)
        guard kind == 101 else { throw AppError.message("SFTP 响应格式无效") }; _ = try status(response)
        committed = true
    }
}
