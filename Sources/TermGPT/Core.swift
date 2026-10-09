import Foundation
import Security

enum SSHAuthentication: String, Codable, CaseIterable {
    case automatic = "SSH config / Agent", password = "密码", key = "私钥"
}
enum ConnectionKind: String, Codable, CaseIterable {
    case ssh, vnc, rdp, web
    var defaultPort: Int { switch self { case .ssh: return 22; case .vnc: return 5900; case .rdp: return 3389; case .web: return 443 } }
    var icon: String { switch self { case .ssh: return "server.rack"; case .vnc: return "display"; case .rdp: return "desktopcomputer"; case .web: return "globe" } }
}
struct BookmarkFolder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "新文件夹"
}
struct Bookmark: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var host = ""
    var port = 22
    var user = ""
    var keyPath = ""
    var folderID: UUID?
    var authentication: SSHAuthentication?
    var notes = ""
    var connectionKind: ConnectionKind?
    var domain: String?
    var clipboardSync: Bool?
    var kind: ConnectionKind { connectionKind ?? .ssh }
    var syncClipboard: Bool { clipboardSync ?? true }
    static func cleanPastedAddress(_ value: String) -> String {
        String(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func webAddress() throws -> URL {
        guard let url = URL(string: host), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), ["http", "https"].contains(parts.scheme?.lowercased() ?? ""), !(parts.host ?? "").isEmpty, parts.user == nil, parts.password == nil, !host.contains(where: { $0.isWhitespace }), !host.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }), parts.port == nil || (1...65535).contains(parts.port!) else { throw AppError.message("请输入有效的 HTTP 或 HTTPS URL，不能包含登录密码") }
        return url
    }
    func validate() throws {
        if kind == .web { _ = try webAddress(); return }
        guard !host.isEmpty, !host.hasPrefix("-"), !host.contains(where: { $0.isWhitespace }), !host.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }), !user.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }), !user.hasPrefix("-"), (1...65535).contains(port) else { throw AppError.message("主机、用户名或端口无效") }
    }
    func arguments() throws -> [String] {
        try validate()
        guard kind == .ssh else { throw AppError.message("远程桌面不能作为 SSH 终端执行") }
        var a = ["-tt", "-p", String(port), "-o", "ServerAliveInterval=30"]
        if !user.isEmpty { a += ["-l", user] }
        if !keyPath.isEmpty && (authentication == nil || authentication == .key) { a += ["-i", NSString(string: keyPath).expandingTildeInPath] }
        a += ["-o", "ProxyJump=none", "-o", "ProxyCommand=none"]
        if authentication == .password { a += ["-o", "PubkeyAuthentication=no", "-o", "PreferredAuthentications=password,keyboard-interactive", "-o", "NumberOfPasswordPrompts=1"] }
        return a + [host]
    }
}
struct Message: Codable, Identifiable {
    var id = UUID()
    var role: String
    var content: String
}
struct Chat: Codable, Identifiable {
    var id = UUID()
    var name = "新聊天"
    var nameIsCustom: Bool?
    var messages: [Message] = []
}
enum ChatActions {
    static func rename(_ id: UUID, title: String, chats: inout [Chat]) -> Bool {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = chats.firstIndex(where: { $0.id == id }) else { return false }
        chats[index].name = String(name.prefix(120)); chats[index].nameIsCustom = true
        return true
    }
    static func delete(_ id: UUID, chats: inout [Chat], selected: inout UUID?) -> Bool {
        guard let index = chats.firstIndex(where: { $0.id == id }) else { return false }
        chats.remove(at: index)
        if chats.isEmpty { chats.append(Chat()) }
        if selected == id || !chats.contains(where: { $0.id == selected }) {
            selected = chats[min(index, chats.count - 1)].id
        }
        return true
    }
}
enum InterfaceTheme: String, Codable, CaseIterable {
    case system = "跟随系统", light = "浅色", dark = "深色"
}
enum ProviderKind: String, Codable, CaseIterable {
    case chatGPT = "ChatGPT", openAI = "OpenAI API", ollama = "Ollama", lmStudio = "LM Studio", custom = "OpenAI-compatible"
    var defaultEndpoint: String {
        switch self {
        case .ollama: return "http://127.0.0.1:11434/v1"
        case .lmStudio: return "http://127.0.0.1:1234/v1"
        default: return "https://api.openai.com/v1"
        }
    }
}
struct Preferences: Codable {
    var provider = ProviderKind.chatGPT
    var chatGPTModel = ""
    var endpoint = "https://api.openai.com/v1"
    var model = ""
    var shell = "/bin/zsh"
    var fontSize = 14.0
    var lightTerminal = false
    var interfaceTheme = InterfaceTheme.system
    var language = InterfaceLanguage.system
    var showBookmarks = true
    var showChat = true
    var saveMemory = true
    var redactBeforeSending = true
    init() {}
    enum CodingKeys: String, CodingKey { case provider, chatGPTModel, endpoint, model, shell, fontSize, lightTerminal, interfaceTheme, language, showBookmarks, showChat, saveMemory, redactBeforeSending }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint) ?? endpoint
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? model
        provider = try c.decodeIfPresent(ProviderKind.self, forKey: .provider) ?? (model.isEmpty && endpoint == ProviderKind.openAI.defaultEndpoint ? .chatGPT : .openAI)
        chatGPTModel = try c.decodeIfPresent(String.self, forKey: .chatGPTModel) ?? ""
        shell = try c.decodeIfPresent(String.self, forKey: .shell) ?? shell
        fontSize = min(24, max(10, try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? fontSize))
        lightTerminal = try c.decodeIfPresent(Bool.self, forKey: .lightTerminal) ?? lightTerminal
        interfaceTheme = try c.decodeIfPresent(InterfaceTheme.self, forKey: .interfaceTheme) ?? .system
        language = try c.decodeIfPresent(InterfaceLanguage.self, forKey: .language) ?? .system
        showBookmarks = try c.decodeIfPresent(Bool.self, forKey: .showBookmarks) ?? true
        showChat = try c.decodeIfPresent(Bool.self, forKey: .showChat) ?? true
        saveMemory = try c.decodeIfPresent(Bool.self, forKey: .saveMemory) ?? saveMemory
        redactBeforeSending = try c.decodeIfPresent(Bool.self, forKey: .redactBeforeSending) ?? true
    }
}
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return L(s) }; return nil }
}
enum ContextMode: String, CaseIterable {
    case auto = "Auto", off = "Off", selected = "Selected text", fifty = "Last 50 lines", twoHundred = "Last 200 lines", entire = "Entire session"
}
enum Safety {
    static func outgoing(_ messages: [Message], redact: Bool) -> [Message] {
        guard redact else { return messages }
        return messages.map { var message = $0; message.content = Safety.redact(message.content); return message }
    }
    static func insertable(_ command: String) -> Bool {
        !command.isEmpty && !command.unicodeScalars.contains { $0.value < 32 || $0.value == 127 || (0x80...0x9f).contains($0.value) || $0.value == 0x2028 || $0.value == 0x2029 }
    }
    static func highRisk(_ command: String) -> Bool {
        // Unknown syntax is conservatively reviewed, never treated as safe.
        if command.trimmingCharacters(in: .whitespaces) == "powermetrics --help" { return false }
        let known = #"^\s*(ls|pwd|cat|grep|head|tail|whoami|hostname|date|uptime|ps|df|du|uname|which|echo|printf|ping|ip|ifconfig|esxcli)\b"#
        let destructive = #"(?i)(\brm\b|\breboot\b|\bshutdown\b|\bmkfs\b|\bdd\b|\bsudo\b|\beval\b|\bexec\b|storage|iptables|opkg\s+remove|prune|[;|&><`\n\r]|\$\()"#
        return command.range(of: known, options: .regularExpression) == nil || command.range(of: destructive, options: .regularExpression) != nil
    }
    static func redact(_ text: String) -> String {
        var result = text
        let patterns = [#"(?is)-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----"#, #"(?im)(authorization\s*:\s*|cookie\s*:\s*)[^\r\n]+"#, #"(?i)\b(password|passwd|token|api[_-]?key|secret|session)\s*[=:]\s*(\"[^\"]*\"|'[^']*'|[^\s,;]+)"#, #"\bsk-[A-Za-z0-9_-]{8,}"#, #"(?i)\bBearer\s+[^\s]+"#]
        for p in patterns { result = result.replacingOccurrences(of: p, with: "[REDACTED]", options: .regularExpression) }
        return result
    }
    static func needsTerminal(_ question: String, names: [String]) -> Bool {
        let q = question.lowercased()
        return names.contains { !$0.isEmpty && q.contains($0.lowercased()) } || ["终端", "命令", "报错", "错误", "输出", "刚才", "这个", "ssh", "terminal", "error", "command", "output", "cpu", "ping", "网络", "温度", "磁盘"].contains { q.contains($0) }
    }
}
struct SavedState: Codable {
    var bookmarks: [Bookmark]
    var folders: [BookmarkFolder]?
    var chats: [Chat]
    var preferences: Preferences
}
enum DiskStore {
    static var directory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TermGPT") }
    static var url: URL { directory.appendingPathComponent("workspace.json") }
    static func load() -> SavedState? {
        guard let data = try? Data(contentsOf: url), var state = try? JSONDecoder().decode(SavedState.self, from: data) else { return nil }
        for index in state.bookmarks.indices { state.bookmarks[index].host = Bookmark.cleanPastedAddress(state.bookmarks[index].host) }
        return state
    }
    static func save(_ state: SavedState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
struct OpenAIProvider {
    let preferences: Preferences
    let key: String
    func stream(messages: [Message], update: @escaping (String) async -> Void) async throws {
        guard let base = URL(string: preferences.endpoint), ["http", "https"].contains(base.scheme), base.host != nil, base.user == nil, base.password == nil, base.query == nil, base.fragment == nil else { throw AppError.message("请输入有效的 API Base URL，例如 https://api.openai.com/v1") }
        if base.scheme == "http" && !["localhost", "127.0.0.1", "::1", "[::1]"].contains(base.host!) { throw AppError.message("远程 API 必须使用 HTTPS；HTTP 仅用于本机模型") }
        guard !preferences.model.trimmingCharacters(in: .whitespaces).isEmpty else { throw AppError.message("请在设置中填写模型名称") }
        var request = URLRequest(url: base.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"; request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": preferences.model, "stream": true, "messages": messages.map { ["role": $0.role, "content": $0.content] }])
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw AppError.message("AI 接口返回 HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)，请检查地址、模型及密钥") }
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8), let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if obj["error"] != nil { throw AppError.message("模型在流式响应中报告错误") }
            if let choices = obj["choices"] as? [[String: Any]], let delta = choices.first?["delta"] as? [String: Any], let content = delta["content"] as? String { await update(content) }
        }
    }
}
