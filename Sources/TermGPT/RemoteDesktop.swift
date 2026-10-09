import AppKit
import SwiftUI
import Darwin

/// Restricted local diagnostics; never records input, clipboard or framebuffer payloads.
final class DesktopLog {
    static let directory = DiskStore.directory.appendingPathComponent("Logs")
    private let handle: FileHandle?
    private let lock = NSLock()
    private let secrets: [String]
    init(bookmark: Bookmark, password: String, directory: URL = DesktopLog.directory) {
        secrets = [password, bookmark.host, bookmark.user, bookmark.domain ?? ""].filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files.filter({ $0.pathExtension == "jsonl" }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).dropFirst(19) { try? FileManager.default.removeItem(at: file) }
        let url = directory.appendingPathComponent("desktop-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        handle = try? FileHandle(forWritingTo: url)
        record("start", "protocol=\(bookmark.kind.rawValue) port=\(bookmark.port)")
    }
    func record(_ event: String, _ detail: String = "") {
        var text = String(detail.prefix(4096))
        for secret in secrets { text = text.replacingOccurrences(of: secret, with: "[redacted]") }
        guard let data = try? JSONSerialization.data(withJSONObject: ["time": ISO8601DateFormatter().string(from: Date()), "event": event, "detail": text]) else { return }
        lock.lock(); defer { lock.unlock() }
        if let offset = try? handle?.offset(), offset < 2 * 1024 * 1024 { try? handle?.write(contentsOf: data + Data([10])) }
    }
    deinit { try? handle?.close() }
}

/// One isolated helper per desktop. Passwords travel only over stdin, never command arguments.
final class RemoteDesktop: ObservableObject {
    @Published var status = "连接中…"
    @Published var connected = false
    @Published var certificate: RemoteCertificate?
    let bookmark: Bookmark
    let view = DesktopCanvas(frame: NSRect(x: 0, y: 0, width: 720, height: 600))
    var changed: (() -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private let writes = DispatchQueue(label: "TermGPT.desktop.input")
    private let reads = DispatchQueue(label: "TermGPT.desktop.output")
    private var clipboardTimer: Timer?
    private var clipboardCount = NSPasteboard.general.changeCount
    private var closed = false
    private var log: DesktopLog?
    private var certificateAlert: NSAlert?
    private var receivedFrame = false
    private var resizeWork: DispatchWorkItem?
    private var lastResize: DesktopResolution?
    private let frameLock = NSLock()
    private var pendingFrame: Data?
    private var frameScheduled = false
    var active = false {
        didSet { if active && !oldValue { syncLocalClipboard(force: true); scheduleResize() } }
    }
    init(bookmark: Bookmark) { self.bookmark = bookmark; view.kind = bookmark.kind; view.send = { [weak self] item in self?.send(item) }; view.firstFrameDrawn = { [weak self] in self?.log?.record("first_frame_drawn") }; view.sizeChanged = { [weak self] in self?.scheduleResize() } }
    private func scheduleResize() {
        resizeWork?.cancel()
        guard active, !closed else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.active, self.connected, !self.closed,
                  let size = DesktopResolution(size: self.view.bounds.size), size != self.lastResize else { return }
            self.lastResize = size
            self.send(["type": "resize", "width": size.width, "height": size.height])
            self.log?.record("resize_requested", "width=\(size.width) height=\(size.height)")
        }
        resizeWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    func start(helperURL: URL? = nil) throws {
        let path = helperURL ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/TermGPTRemoteDesktop")
        guard FileManager.default.isExecutableFile(atPath: path.path) else { throw AppError.message("缺少远程桌面组件，请使用完整安装包") }
        let password = try SSHPasswordStore.read(id: bookmark.id) ?? ""
        // EPIPE from a helper that has exited must not terminate the application.
        signal(SIGPIPE, SIG_IGN)
        log = DesktopLog(bookmark: bookmark, password: password)
        let task = Process(), stdin = Pipe(), stdout = Pipe()
        task.executableURL = path; task.standardInput = stdin; task.standardOutput = stdout; task.standardError = FileHandle.nullDevice
        task.environment = Self.helperEnvironment
        try task.run(); process = task; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        let size = DesktopResolution(size: view.bounds.size) ?? DesktopResolution(size: NSSize(width: 720, height: 600))!
        send(["protocol": bookmark.kind.rawValue, "host": bookmark.host, "port": bookmark.port, "user": bookmark.user, "password": password, "domain": bookmark.domain ?? "", "clipboard": bookmark.syncClipboard, "width": size.width, "height": size.height])
        let handle = stdout.fileHandleForReading
        let logger = log
        task.terminationHandler = { task in logger?.record("helper_exit", "code=\(task.terminationStatus) reason=\(task.terminationReason.rawValue)") }
        reads.async { [weak self] in
            defer { try? handle.close() }
            var decoder = DesktopPacketDecoder()
            do {
                // POSIX pipe reads return available bytes immediately. Foundation's counted read
                // can wait for more bytes, deadlocking a small certificate challenge until EOF.
                var bytes = [UInt8](repeating: 0, count: 65536)
                while true {
                    let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
                    if count == 0 { break }
                    if count < 0 { if errno == EINTR { continue }; throw AppError.message("远程桌面连接中断") }
                    let data = Data(bytes.prefix(count))
                    for packet in try decoder.append(data) {
                        if packet.kind == 1 { self?.enqueueFrame(packet.data) }
                        else { DispatchQueue.main.async { [weak self] in self?.receive(packet) } }
                    }
                }
                DispatchQueue.main.async { [weak self] in self?.ended() }
            } catch { DispatchQueue.main.async { [weak self] in self?.ended(message: L("远程桌面连接中断")) } }
        }
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in self?.syncLocalClipboard() }
    }
    static var helperEnvironment: [String: String] {
        ["PATH": "/usr/bin:/bin", "WLOG_LEVEL": "OFF", "HOME": FileManager.default.homeDirectoryForCurrentUser.path, "TMPDIR": NSTemporaryDirectory(), "LANG": "en_US.UTF-8"]
    }
    func send(_ item: [String: Any]) {
        guard !closed, let handle = input, var data = try? JSONSerialization.data(withJSONObject: item) else { return }
        data.append(10)
        let logger = log
        writes.async { do { try handle.write(contentsOf: data) } catch { logger?.record("input_pipe_closed") } }
    }
    private func enqueueFrame(_ data: Data) {
        frameLock.lock(); pendingFrame = data
        let schedule = !frameScheduled; frameScheduled = true; frameLock.unlock()
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.frameLock.lock(); let latest = self.pendingFrame; self.pendingFrame = nil; self.frameScheduled = false; self.frameLock.unlock()
            if let latest { self.receive(DesktopPacket(kind: 1, data: latest)) }
        }
    }
    private func receive(_ packet: DesktopPacket) {
        guard !closed else { return }
        switch packet.kind {
        case 1: if let image = DesktopFrame.decode(packet.data) {
            if !receivedFrame { receivedFrame = true; log?.record("first_frame_received", "width=\(image.width) height=\(image.height)") }
            view.image = image
        }
        case 2:
            let message = String(decoding: packet.data, as: UTF8.self)
            log?.record("status", message)
            if message == "connected" { connected = true; status = L("已连接"); syncLocalClipboard(force: true); scheduleResize() }
            else if message == "connecting" { status = L("连接中…") }
            else if message == "disconnected" { connected = false; status = L("已断开") }
            else {
                connected = false
                if message.hasPrefix("RDP connection failed ("), let code = message.split(separator: "(").last?.split(separator: ")").first {
                    status = L("RDP 连接失败（%@），请检查登录信息、证书和远程桌面服务。", String(code))
                } else if message.hasPrefix("VNC connection failed") { status = L("VNC 连接失败，请检查密码、主机和 VNC 服务。") }
                else { status = L(message) }
            }
            changed?()
        case 3:
            guard active, connected, bookmark.syncClipboard, packet.data.count <= 1024 * 1024, let text = String(data: packet.data, encoding: .utf8) else { return }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); clipboardCount = NSPasteboard.general.changeCount
        case 4:
            log?.record("certificate", "approval requested")
            if let values = try? JSONDecoder().decode(RemoteCertificate.self, from: packet.data) {
                certificate = values
                if (try? RDPCertificateTrust.matches(id: bookmark.id, host: bookmark.host, port: bookmark.port, certificate: values)) == true {
                    log?.record("certificate", "saved certificate fingerprint matched"); answerCertificate(true)
                } else { status = L("等待确认证书"); presentCertificate() }
                changed?()
            }
        case 5: status = L("当前 VNC 服务器不支持 Unicode 剪贴板文本。"); changed?()
        case 6: log?.record("protocol", String(decoding: packet.data, as: UTF8.self))
        default: break
        }
    }
    private func syncLocalClipboard(force: Bool = false) {
        let pasteboard = NSPasteboard.general
        guard force || pasteboard.changeCount != clipboardCount else { return }
        clipboardCount = pasteboard.changeCount
        guard active, connected, bookmark.syncClipboard, let text = pasteboard.string(forType: .string), text.utf8.count <= 1024 * 1024 else { return }
        send(["type": "clipboard", "text": text])
    }
    func answerCertificate(_ accept: Bool, remember: Bool = false) {
        if accept && remember, let certificate {
            do { try RDPCertificateTrust.remember(id: bookmark.id, host: bookmark.host, port: bookmark.port, certificate: certificate) }
            catch { status = L("无法保存证书信任，请重试"); changed?(); return }
        }
        log?.record("certificate", accept ? (remember ? "certificate trust saved" : "accepted for this session") : "rejected")
        send(["type": "certificate", "accept": accept]); certificate = nil
    }
    func presentCertificate() {
        guard !closed, active, let certificate, certificateAlert == nil, let window = view.window, window.attachedSheet == nil else { return }
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = L("验证 RDP 服务器证书")
        alert.informativeText = L("无法验证服务器证书。请核对服务器身份。始终信任会保存此主机和端口的证书指纹，证书变更时重新询问。") + "\n\n" + certificate.host + ":" + String(bookmark.port) + "\n" + certificate.subject + "\n" + certificate.issuer + "\n" + certificate.fingerprint
        alert.addButton(withTitle: L("仅本次信任")); alert.addButton(withTitle: L("始终信任")); alert.addButton(withTitle: L("取消"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        certificateAlert = alert
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }; self.certificateAlert = nil
            guard !self.closed else { return }
            self.answerCertificate(response == .alertFirstButtonReturn || response == .alertSecondButtonReturn, remember: response == .alertSecondButtonReturn)
        }
    }
    private func ended(message: String? = nil) {
        guard !closed else { return }; connected = false
        if let message { status = message } else if status == L("已连接") || status == L("连接中…") { status = L("已断开") }
        clipboardTimer?.invalidate(); changed?()
    }
    func close() {
        resizeWork?.cancel(); resizeWork = nil
        guard !closed else { return }; send(["type": "stop"]); closed = true
        log?.record("close", "user closed tab")
        if let alert = certificateAlert, let parent = alert.window.sheetParent { parent.endSheet(alert.window, returnCode: .abort) }
        certificateAlert = nil
        clipboardTimer?.invalidate(); clipboardTimer = nil; connected = false
        let task = process, handle = input
        writes.async { try? handle?.close(); if task?.isRunning == true { task?.terminate() } }
        // The reader owns stdout until EOF; never close it during a blocking read.
        output = nil; input = nil; certificate = nil; view.send = nil; view.sizeChanged = nil; changed = nil
    }
    deinit { clipboardTimer?.invalidate(); if process?.isRunning == true { process?.terminate() } }
}
struct RemoteCertificate: Codable, Identifiable {
    var id: String { host + fingerprint }
    let host: String
    let subject: String
    let issuer: String
    let fingerprint: String
}
struct DesktopPacket { let kind: UInt8; let data: Data }
struct DesktopPacketDecoder {
    private var buffer = Data()
    mutating func append(_ data: Data) throws -> [DesktopPacket] {
        buffer.append(data); var packets: [DesktopPacket] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard length >= 1 && length <= 40 * 1024 * 1024 else { throw AppError.message("远程桌面数据无效") }
            guard buffer.count >= length + 4 else { break }
            packets.append(DesktopPacket(kind: buffer[buffer.startIndex + 4], data: Data(buffer.dropFirst(5).prefix(length - 1))))
            buffer.removeFirst(length + 4)
        }
        return packets
    }
}
enum DesktopFrame {
    static func decode(_ data: Data) -> CGImage? {
        guard data.count >= 8 else { return nil }
        let width = data.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        let height = data.dropFirst(4).prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard (1...4096).contains(width), (1...2160).contains(height), data.count == 8 + width * height * 4,
              let provider = CGDataProvider(data: Data(data.dropFirst(8)) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
struct DesktopHost: NSViewRepresentable {
    let desktop: RemoteDesktop
    let active: Bool
    func makeNSView(context: Context) -> DesktopCanvas { desktop.view }
    func updateNSView(_ view: DesktopCanvas, context: Context) {
        desktop.active = active
        view.needsDisplay = true
        if active { DispatchQueue.main.async { [weak desktop] in desktop?.presentCertificate() } }
        if !active && view.window?.firstResponder === view { view.window?.makeFirstResponder(nil) }
    }
}
struct DesktopPane: View {
    @ObservedObject var desktop: RemoteDesktop
    let active: Bool
    var body: some View {
        DesktopHost(desktop: desktop, active: active)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if !desktop.connected {
                    Text(L(desktop.status)).padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .allowsHitTesting(false)
                }
            }
    }
}
struct DesktopTabActions: View {
    @ObservedObject var desktop: RemoteDesktop
    var body: some View {
                Text(L(desktop.status))
                if desktop.certificate != nil { Button(L("验证 RDP 服务器证书")) { desktop.presentCertificate() } }
                Button(L("打开连接日志")) { NSWorkspace.shared.open(DesktopLog.directory) }
                if desktop.bookmark.kind == .rdp {
                    Button("Ctrl+Alt+Del") { desktop.send(["type": "key", "scan": 0x1d, "keysym": 0xffe3, "down": true]); desktop.send(["type": "key", "scan": 0x38, "keysym": 0xffe9, "down": true]); desktop.send(["type": "key", "scan": 0x153, "keysym": 0xffff, "down": true]); desktop.send(["type": "key", "scan": 0x153, "keysym": 0xffff, "down": false]); desktop.send(["type": "key", "scan": 0x38, "keysym": 0xffe9, "down": false]); desktop.send(["type": "key", "scan": 0x1d, "keysym": 0xffe3, "down": false]) }
                }
    }
}
/// Scales a framebuffer with correct pointer mapping; hardware keys preserve remote shortcuts.
final class DesktopCanvas: NSView {
    var sizeChanged: (() -> Void)?
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); sizeChanged?() }
    override func viewDidEndLiveResize() { super.viewDidEndLiveResize(); sizeChanged?() }
    var kind: ConnectionKind = .rdp
    var image: CGImage? { didSet { presentFrame() } }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; presentFrame() }
    required init?(coder: NSCoder) { super.init(coder: coder); wantsLayer = true; presentFrame() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { presentFrame() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); presentFrame() }
    private func presentFrame() {
        // Set the backing layer directly: a SwiftUI-hosted NSView may defer draw(_:) until input.
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
        layer?.contents = image
        if image != nil, window != nil { firstFrameDrawn?(); firstFrameDrawn = nil }
    }
    var send: (([String: Any]) -> Void)?
    var firstFrameDrawn: (() -> Void)?
    private var buttons = 0
    private var modifiers: NSEvent.ModifierFlags = []
    private var pressedSymbols: [UInt16: Int] = [:]
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)); super.updateTrackingAreas()
    }
    var imageRect: NSRect {
        guard let image, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let size = NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return NSRect(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2, width: size.width, height: size.height)
    }
    private func mouse(_ event: NSEvent, flags: Int) {
        guard let image, !imageRect.isEmpty else { return }
        let point = convert(event.locationInWindow, from: nil), rect = imageRect
        let x = max(0, min(image.width-1, Int((point.x-rect.minX)/rect.width*CGFloat(image.width))))
        let y = max(0, min(image.height-1, Int((point.y-rect.minY)/rect.height*CGFloat(image.height))))
        send?(["type": "mouse", "x": x, "y": y, "flags": flags, "buttons": buttons])
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); buttons |= 1; mouse(event, flags: 0x9000) }
    override func mouseUp(with event: NSEvent) { buttons &= ~1; mouse(event, flags: 0x1000) }
    override func rightMouseDown(with event: NSEvent) { window?.makeFirstResponder(self); buttons |= 4; mouse(event, flags: 0xa000) }
    override func rightMouseUp(with event: NSEvent) { buttons &= ~4; mouse(event, flags: 0x2000) }
    override func otherMouseDown(with event: NSEvent) { buttons |= 2; mouse(event, flags: 0xc000) }
    override func otherMouseUp(with event: NSEvent) { buttons &= ~2; mouse(event, flags: 0x4000) }
    override func mouseMoved(with event: NSEvent) { if window?.firstResponder === self { mouse(event, flags: 0x0800) } }
    override func mouseDragged(with event: NSEvent) { mouse(event, flags: 0x0800) }
    override func rightMouseDragged(with event: NSEvent) { mouse(event, flags: 0x0800) }
    override func scrollWheel(with event: NSEvent) {
        guard event.scrollingDeltaY != 0 else { return }
        let saved = buttons; buttons |= event.scrollingDeltaY > 0 ? 8 : 16
        mouse(event, flags: event.scrollingDeltaY > 0 ? 0x0278 : 0x0388); buttons = saved; mouse(event, flags: 0x0800)
    }
    override func keyDown(with event: NSEvent) { key(event, down: true) }
    override func keyUp(with event: NSEvent) { key(event, down: false) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }; key(event, down: true); return true
    }
    private func key(_ event: NSEvent, down: Bool) {
        if let mapping = DesktopKeys.keys[event.keyCode] {
            var symbol = mapping.1
            if kind == .vnc && mapping.1 < 0xff00 {
                if down, let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first { symbol = Int(scalar.value <= 255 ? scalar.value : scalar.value | 0x01000000); pressedSymbols[event.keyCode] = symbol }
                else if let pressed = pressedSymbols.removeValue(forKey: event.keyCode) { symbol = pressed }
            }
            send?(["type": "key", "scan": mapping.0, "keysym": symbol, "down": down])
        }
        else if down, let text = event.characters, !text.isEmpty { send?(["type": "text", "text": text]) }
    }
    override func flagsChanged(with event: NSEvent) {
        var next = event.modifierFlags
        if kind == .rdp && next.contains(.command) { next.insert(.control); next.remove(.command) }
        for (flag, scan, symbol) in [(NSEvent.ModifierFlags.shift,0x2a,0xffe1),(.control,0x1d,0xffe3),(.option,0x38,0xffe9),(.command,0x15b,0xffe7)] {
            if modifiers.contains(flag) != next.contains(flag) { send?(["type": "key", "scan": scan, "keysym": symbol, "down": next.contains(flag)]) }
        }
        modifiers = next
    }
    override func resignFirstResponder() -> Bool {
        for (key,symbol) in pressedSymbols { if let scan = DesktopKeys.keys[key]?.0 { send?(["type":"key", "scan":scan,"keysym":symbol,"down":false]) } }; pressedSymbols = [:]
        for (flag,scan,symbol) in [(NSEvent.ModifierFlags.shift,0x2a,0xffe1),(.control,0x1d,0xffe3),(.option,0x38,0xffe9),(.command,0x15b,0xffe7)] where modifiers.contains(flag) { send?(["type":"key", "scan":scan,"keysym":symbol,"down":false]) }
        modifiers = []; return super.resignFirstResponder()
    }
}
enum DesktopKeys {
    // macOS virtual keycode -> Windows set-1 scancode (extended bit 0x100), X11 keysym.
    static let keys: [UInt16: (Int, Int)] = [
        0:(0x1e,0x61),1:(0x1f,0x73),2:(0x20,0x64),3:(0x21,0x66),4:(0x23,0x68),5:(0x22,0x67),6:(0x2c,0x7a),7:(0x2d,0x78),8:(0x2e,0x63),9:(0x2f,0x76),11:(0x30,0x62),12:(0x10,0x71),13:(0x11,0x77),14:(0x12,0x65),15:(0x13,0x72),16:(0x15,0x79),17:(0x14,0x74),18:(0x02,0x31),19:(0x03,0x32),20:(0x04,0x33),21:(0x05,0x34),22:(0x07,0x36),23:(0x06,0x35),24:(0x0d,0x3d),25:(0x0a,0x39),26:(0x08,0x37),27:(0x0c,0x2d),28:(0x09,0x38),29:(0x0b,0x30),30:(0x1b,0x5d),31:(0x18,0x6f),32:(0x16,0x75),33:(0x1a,0x5b),34:(0x17,0x69),35:(0x19,0x70),36:(0x1c,0xff0d),37:(0x26,0x6c),38:(0x24,0x6a),39:(0x28,0x27),40:(0x25,0x6b),41:(0x27,0x3b),42:(0x2b,0x5c),43:(0x33,0x2c),44:(0x35,0x2f),45:(0x31,0x6e),46:(0x32,0x6d),47:(0x34,0x2e),48:(0x0f,0xff09),49:(0x39,0x20),50:(0x29,0x60),51:(0x0e,0xff08),53:(0x01,0xff1b),65:(0x53,0xffae),67:(0x37,0xffaa),69:(0x4e,0xffab),71:(0x145,0xff0b),75:(0x135,0xffaf),76:(0x11c,0xff8d),78:(0x4a,0xffad),82:(0x52,0xffb0),83:(0x4f,0xffb1),84:(0x50,0xffb2),85:(0x51,0xffb3),86:(0x4b,0xffb4),87:(0x4c,0xffb5),88:(0x4d,0xffb6),89:(0x47,0xffb7),91:(0x48,0xffb8),92:(0x49,0xffb9),96:(0x3f,0xffc2),97:(0x40,0xffc3),98:(0x41,0xffc4),99:(0x3d,0xffc0),100:(0x42,0xffc5),101:(0x43,0xffc6),103:(0x57,0xffc8),109:(0x44,0xffc7),111:(0x58,0xffc9),115:(0x147,0xff50),116:(0x149,0xff55),117:(0x153,0xffff),118:(0x3e,0xffc1),119:(0x14f,0xff57),120:(0x3c,0xffbf),121:(0x151,0xff56),122:(0x3b,0xffbe),123:(0x14b,0xff51),124:(0x14d,0xff53),125:(0x150,0xff54),126:(0x148,0xff52)
    ]
}
