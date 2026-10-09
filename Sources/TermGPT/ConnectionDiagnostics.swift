import AppKit
import SwiftUI
import Network

/// Classification uses protocol errors only. It never guesses credentials from TCP reachability.
enum ConnectionFailure {
    static func canRetry(_ message: String) -> Bool {
        let text = message.lowercased()
        let blocked = ["permission denied", "authentication failed", "password check failed", "host key verification failed", "remote host identification has changed", "0x00020008", "0x00020009", "0x0002000a", "0x0002000b", "0x0002000c", "0x0002000e", "0x0002000f", "0x00020012", "0x00020013", "0x00020014", "0x00020015"]
        return !blocked.contains(where: text.contains)
    }
    static func explanation(_ message: String) -> String {
        let text = message.lowercased()
        if text.contains("0x00020004") || text.contains("0x00020005") || text.contains("resolve") || text.contains("name or service") { return L("无法解析主机名，请检查地址或 DNS。") }
        if text.contains("0x00020009") || text.contains("0x00020014") || text.contains("0x00020015") || text.contains("authentication failed") || text.contains("password check failed") || text.contains("permission denied") { return L("身份验证失败，请检查用户名、密码或私钥。") }
        if text.contains("0x00020008") || text.contains("0x0002000c") { return L("TLS 或安全协议协商失败，请检查证书及服务端协议设置。") }
        if text.contains("0x0002000e") || text.contains("0x0002000f") || text.contains("0x00020013") { return L("密码已过期或必须更改，请在服务端更新密码。") }
        if text.contains("0x0002000a") || text.contains("0x00020012") { return L("账户被禁用或没有远程登录权限。") }
        if text.contains("0x00020006") || text.contains("0x0002000d") || text.contains("unable to connect") || text.contains("connection refused") || text.contains("timed out") { return L("无法建立网络连接，请检查端口、服务、防火墙及本地网络权限。") }
        if text.contains("host key verification failed") || text.contains("remote host identification has changed") { return L("SSH 主机指纹验证失败，请核对服务器身份及 known_hosts。") }
        return L("连接已结束。可检查网络端口及连接日志；端口可达不代表登录成功。")
    }
}
final class ConnectionDiagnostic: ObservableObject {
    @Published var result = ""
    @Published var checking = false
    let bookmark: Bookmark
    let failure: String
    private var connection: NWConnection?
    private var timeout: DispatchWorkItem?
    private var generation = UUID()
    init(bookmark: Bookmark, failure: String) { self.bookmark = bookmark; self.failure = failure }
    func run() {
        cancel(); checking = true; result = L("正在检查主机与端口…")
        let token = generation, bookmark = bookmark
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var host = bookmark.host, port = bookmark.port
            if bookmark.kind == .ssh {
                let process = Process(), pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = ["-G"] + ((try? bookmark.arguments()) ?? [bookmark.host])
                process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                        let fields = line.split(separator: " ", maxSplits: 1)
                        if fields.count == 2 && fields[0] == "hostname" { host = String(fields[1]) }
                        if fields.count == 2 && fields[0] == "port", let value = Int(fields[1]) { port = value }
                    }
                } catch { }
            }
            let resolvedHost = host, resolvedPort = port
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: resolvedPort)) else { self.finish(L("端口无效"), token: token); return }
                let connection = NWConnection(host: NWEndpoint.Host(resolvedHost), port: port, using: .tcp)
                self.connection = connection
                connection.stateUpdateHandler = { [weak self] state in
                    DispatchQueue.main.async {
                        switch state {
                        case .ready: self?.finish(L("TCP 端口可达。请继续核对登录信息、证书和服务端协议；此检查不会尝试登录。"), token: token)
                        case .failed(let error): self?.finish(L("网络检查失败：%@", error.localizedDescription), token: token)
                        default: break
                        }
                    }
                }
                let work = DispatchWorkItem { [weak self] in self?.finish(L("连接超时。请检查主机、端口、服务、防火墙和 macOS 本地网络权限。"), token: token) }
                self.timeout = work; DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
                connection.start(queue: DispatchQueue.global(qos: .utility))
            }
        }
    }
    private func finish(_ text: String, token: UUID) {
        guard generation == token, checking else { return }
        result = text; checking = false; timeout?.cancel(); connection?.cancel(); connection = nil
    }
    func cancel() { generation = UUID(); timeout?.cancel(); connection?.cancel(); connection = nil; checking = false }
    deinit { connection?.cancel(); timeout?.cancel() }
}
struct DiagnosticPane: View {
    @StateObject var diagnostic: ConnectionDiagnostic
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("连接诊断")).font(.title2.bold())
            Text("\(diagnostic.bookmark.kind.rawValue.uppercased()) · \(diagnostic.bookmark.host):\(diagnostic.bookmark.port)").textSelection(.enabled)
            Text(ConnectionFailure.explanation(diagnostic.failure)).textSelection(.enabled)
            Divider()
            Text(diagnostic.result).textSelection(.enabled)
            Text(L("仅检查 TCP，不发送密码、不修改服务端，也不会绕过证书验证。")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L("重新检查")) { diagnostic.run() }.disabled(diagnostic.checking)
                Button(L("打开连接日志")) { NSWorkspace.shared.open(DesktopLog.directory) }
                if diagnostic.checking { ProgressView().controlSize(.small) }
            }
        }.padding(24).frame(width: 520).onAppear { diagnostic.run() }.onDisappear { diagnostic.cancel() }
    }
}
final class DiagnosticWindow {
    private static var window: NSWindow?
    static func show(bookmark: Bookmark, failure: String) {
        window?.close()
        let pane = DiagnosticPane(diagnostic: ConnectionDiagnostic(bookmark: bookmark, failure: failure))
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 570, height: 310), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.title = L("连接诊断"); panel.contentView = NSHostingView(rootView: pane)
        window = panel; panel.center(); panel.makeKeyAndOrderFront(nil)
    }
}
struct ConnectionTabActions: View {
    @ObservedObject var session: TerminalSession
    let preferences: Preferences
    var body: some View {
        Button(L("重连")) { do { try session.reconnect(preferences) } catch { session.status = error.localizedDescription } }.disabled(session.running || session.connecting)
        Toggle(L("断线自动重连"), isOn: $session.autoReconnect)
        if let bookmark = session.bookmark {
            Button(L("连接诊断")) { DiagnosticWindow.show(bookmark: bookmark, failure: session.diagnosticMessage) }
        }
    }
}
